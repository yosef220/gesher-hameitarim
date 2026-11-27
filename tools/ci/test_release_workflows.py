"""Offline versioning and release publisher state-machine regressions."""
from copy import deepcopy
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from github_read import GitHubReadError
import publish_release as pub
from release_version import API, REPOSITORY, REPOSITORY_ID, build_version, installer_name, portable_name, stable_version


HEAD = 'a' * 40
MAIN = 'b' * 40
# גשר המיתרים: ראש ענף המוצר, שממנו יוצאות הגרסאות.
PRODUCT = '9' * 40
BLOB = 'c' * 40
ANNOTATED = 'd' * 40
TAG = 'v0.2.1'
RUN = 101
ATTEMPT = 2
SUITE = 111
PUBLISH_RUN = 201
WORKFLOW = 202
PACKAGE = 301
ARCHIVE = 401
DRAFT = 501
CLAIM = 'f' * 64
DIGEST = 'sha256:' + 'e' * 64
START = '2026-01-18T13:00:00Z'
CREATED = '2026-01-18T13:01:00Z'
END = '2026-01-18T13:02:00Z'
REPO = {'id': REPOSITORY_ID, 'full_name': REPOSITORY}
SOURCE = pub.Source(TAG, HEAD, RUN, ATTEMPT, SUITE)
ISSUER = pub.Issuer(WORKFLOW, PUBLISH_RUN, 2, MAIN)
PREVIOUS = pub.Issuer(WORKFLOW, PUBLISH_RUN, 1, MAIN)
PAYLOAD = b'tested installer bytes; never executed by the publisher'
PORTABLE_PAYLOAD = b'tested portable ZIP bytes; never executed by the publisher'


def release_row(identity, tag, *, draft=False, prerelease=False):
    name = installer_name(stable_version(tag)) if stable_version(tag) else 'invalid'
    return {
        'id': identity, 'tag_name': tag, 'draft': draft, 'prerelease': prerelease,
        'published_at': None if draft else END,
        'html_url': f'https://github.com/{REPOSITORY}/releases/tag/{tag}',
        'assets': [{
            'id': identity * 10, 'name': name, 'state': 'uploaded', 'size': 33, 'digest': DIGEST,
            'browser_download_url': f'https://github.com/{REPOSITORY}/releases/download/{tag}/{name}',
        }],
    }


class BuildVersionTests(unittest.TestCase):
    def setUp(self):
        self.env = {'GITHUB_REPOSITORY': REPOSITORY, 'GITHUB_REPOSITORY_ID': str(REPOSITORY_ID),
                    'GITHUB_REF': 'refs/heads/main', 'GITHUB_EVENT_NAME': 'push', 'GITHUB_RUN_NUMBER': '526'}
        invalid = release_row(7, 'v9.0.0')
        invalid['assets'][0]['digest'] = None
        missing_installer = release_row(8, 'v8.0.0')
        missing_installer['assets'] = []
        self.catalog = [
            release_row(1, 'v0.2.8'), release_row(2, '0.2.10'), release_row(3, 'v9.0.0', prerelease=True),
            release_row(4, 'v10.0.0', draft=True), release_row(5, 'v1.2.3-rc1'),
            release_row(6, 'v01.0.0'), invalid, missing_installer,
        ]

    def read(self, endpoint):
        self.assertEqual(endpoint, f'{API}/releases?per_page=100&page=1')
        return self.catalog

    def test_only_actual_upstream_tag_push_gets_three_components(self):
        self.env['GITHUB_REF'] = f'refs/tags/{TAG}'
        self.assertEqual(build_version(self.env, lambda _: self.fail('Tag build must not use the release feed')), '0.2.1')
        for tag in ('v0.1.65535', 'v00.2.1', 'v65536.1.1', 'v0.2.1-rc1'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                build_version(dict(self.env, GITHUB_REF=f'refs/tags/{tag}'), self.read)

    def test_main_pr_and_manual_branch_dispatch_use_highest_eligible_release(self):
        self.assertEqual(build_version(self.env, self.read), '0.2.10.526')
        self.assertEqual(build_version(dict(self.env, GITHUB_REF='refs/pull/11/merge',
                                            GITHUB_EVENT_NAME='pull_request'), self.read), '0.2.10.526')
        self.assertEqual(build_version(dict(self.env, GITHUB_REF='refs/heads/product',
                                            GITHUB_EVENT_NAME='workflow_dispatch'), self.read), '0.2.10.526')

    def test_manual_dispatch_on_a_release_tag_builds_that_release(self):
        # גשר המיתרים: בפורק, גרסה נבנית בהפעלה ידנית של ה-CI על התג.
        dispatch = dict(self.env, GITHUB_REF='refs/tags/v9.0.0', GITHUB_EVENT_NAME='workflow_dispatch')
        self.assertEqual(build_version(dispatch, lambda _: self.fail('Tag build must not use the release feed')), '9.0.0')
        for tag in ('v0.1.65535', 'v9.0.0-rc1'):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                build_version(dict(dispatch, GITHUB_REF=f'refs/tags/{tag}'), self.read)
        self.assertEqual(build_version(dict(dispatch, GITHUB_EVENT_NAME='schedule'), self.read), '0.2.10.526')

    def test_standalone_fork_has_canonical_public_baseline_even_on_tag_push(self):
        fork = dict(self.env, GITHUB_REPOSITORY='fork/gesher', GITHUB_REPOSITORY_ID='55',
                    GITHUB_REF='refs/tags/v9.0.0')
        self.assertEqual(build_version(fork, self.read), '0.2.10.526')

    def test_no_release_seed_and_no_seed_on_api_failure(self):
        self.assertEqual(build_version(self.env, lambda _: []), '0.0.0.526')
        with self.assertRaises(GitHubReadError):
            build_version(self.env, lambda _: (_ for _ in ()).throw(GitHubReadError('unavailable')))
        with self.assertRaises(ValueError):
            build_version(dict(self.env, GITHUB_RUN_NUMBER='65536'), self.read)


def make_job(name, identity, steps=(), *, run=RUN, attempt=ATTEMPT, head=HEAD):
    return {'name': name, 'id': identity, 'status': 'completed', 'conclusion': 'success',
            'run_id': run, 'run_attempt': attempt, 'head_sha': head, 'started_at': START, 'completed_at': END,
            'steps': [{'name': step, 'status': 'completed', 'conclusion': 'success'} for step in steps]}


class StubGitHub:
    def __init__(self):
        self.calls = []
        self.tag = {'ref': f'refs/tags/{TAG}', 'object': {'type': 'tag', 'sha': ANNOTATED}}
        self.comparison = {'status': 'ahead', 'base_commit': {'sha': HEAD}, 'merge_base_commit': {'sha': HEAD}}
        # כברירת מחדל הקומיט שנבדק לא בענף המוצר. הבדיקות של המוצר משנות את זה.
        self.product_comparison = {'status': 'diverged', 'base_commit': {'sha': HEAD}, 'merge_base_commit': {'sha': MAIN}}
        self.product_exists = True
        self.product_ci_definition = {'type': 'file', 'path': pub.CI_PATH, 'sha': BLOB}
        self.ci_definition = {'type': 'file', 'path': pub.CI_PATH, 'sha': BLOB}
        self.ci_run = {'id': RUN, 'run_attempt': ATTEMPT, 'check_suite_id': SUITE, 'head_sha': HEAD,
                       'name': 'ci', 'workflow_id': pub.CI_ID, 'path': pub.CI_PATH, 'event': 'push',
                       'head_branch': TAG, 'status': 'completed', 'conclusion': 'success',
                       'repository': REPO, 'head_repository': REPO}
        self.issuer_path = pub.PUBLISH_PATH
        self.ci_jobs = [make_job('source-identity', 21, [pub.RELEASE_STEP]),
                        make_job('ci-required', 22), make_job('package', PACKAGE, [pub.UPLOAD_STEP])]
        self.artifact = {
            'name': pub.ARTIFACT_NAME, 'id': ARCHIVE, 'size_in_bytes': 333, 'digest': DIGEST,
            'expired': False, 'created_at': CREATED, 'workflow_run': {
                'id': RUN, 'repository_id': REPOSITORY_ID, 'head_repository_id': REPOSITORY_ID,
                'head_branch': TAG, 'head_sha': HEAD,
            },
        }
        self.extra_artifacts = []
        self.artifact_total = None
        self.issuer_event = 'workflow_run'
        self.releases = []
        self.on_upload = lambda: None
        self.on_patch = lambda: None
        self.patch_mode = 'success'
        self.get_release_unavailable = False
        self.download_called = False
        self.corrupt_checksum = False

    def get(self, endpoint):
        self.calls.append(('GET', endpoint))
        if endpoint == f'{API}/actions/runs/{RUN}':
            return deepcopy(self.ci_run)
        if endpoint == f'{API}/git/ref/tags/{TAG}':
            if self.tag is None:
                raise GitHubReadError('tag deleted')
            return deepcopy(self.tag)
        if endpoint == f'{API}/git/tags/{ANNOTATED}':
            return {'sha': ANNOTATED, 'object': {'type': 'commit', 'sha': HEAD}}
        if endpoint == f'{API}/git/ref/heads/main':
            return {'ref': 'refs/heads/main', 'object': {'sha': MAIN, 'type': 'commit'}}
        if endpoint == f'{API}/compare/{HEAD}...{MAIN}':
            return deepcopy(self.comparison)
        if endpoint == f'{API}/git/ref/heads/product':
            if not self.product_exists:
                raise GitHubReadError('Not Found')
            return {'ref': 'refs/heads/product', 'object': {'sha': PRODUCT, 'type': 'commit'}}
        if endpoint == f'{API}/compare/{HEAD}...{PRODUCT}':
            return deepcopy(self.product_comparison)
        if endpoint == f'{API}/contents/{pub.CI_PATH}?ref=product':
            return deepcopy(self.product_ci_definition)
        if endpoint == f'{API}/compare/{MAIN}...{MAIN}':
            return {'status': 'identical', 'base_commit': {'sha': MAIN}, 'merge_base_commit': {'sha': MAIN}}
        if endpoint == f'{API}/contents/{pub.CI_PATH}?ref={HEAD}':
            return deepcopy(self.ci_definition)
        if endpoint.startswith(f'{API}/actions/runs/{RUN}/artifacts?per_page=100&page='):
            # גשר המיתרים: כמו GitHub, ‏100 בכל דף. אחרי הרצות חוזרות יש בריצה artifacts מכל הניסיונות.
            rows = [deepcopy(self.artifact)] + deepcopy(self.extra_artifacts)
            page = int(endpoint.rsplit('=', 1)[1])
            total = len(rows) if self.artifact_total is None else self.artifact_total
            return {'total_count': total, 'artifacts': rows[(page - 1) * 100:page * 100]}
        if endpoint == f'{API}/actions/runs/{PUBLISH_RUN}/attempts/1':
            return {'id': PUBLISH_RUN, 'run_attempt': 1, 'workflow_id': WORKFLOW, 'path': self.issuer_path,
                    'name': pub.PUBLISH_NAME, 'head_branch': 'main', 'head_sha': MAIN, 'event': self.issuer_event,
                    'status': 'completed', 'repository': REPO, 'head_repository': REPO}
        if endpoint == f'{API}/releases?per_page=100&page=1':
            return deepcopy(self.releases)
        if endpoint == f'{API}/releases/{DRAFT}':
            if self.get_release_unavailable:
                raise GitHubReadError('release view unavailable')
            return deepcopy(self.own)
        raise AssertionError(f'Unexpected GET: {endpoint}')

    def jobs(self, endpoint):
        if endpoint == f'{API}/actions/runs/{RUN}/attempts/{ATTEMPT}/jobs':
            return {'jobs': deepcopy(self.ci_jobs)}
        if endpoint == f'{API}/actions/runs/{PUBLISH_RUN}/attempts/1/jobs':
            return {'jobs': [make_job('publish', 909, [pub.PUBLISH_STEP], run=PUBLISH_RUN, attempt=1, head=MAIN)]}
        raise AssertionError(f'Unexpected jobs endpoint: {endpoint}')

    def job_log(self, job_id):
        assert job_id == 909
        return f'2026-01-18T13:00:00.1234567Z GESHER_RELEASE_DRAFT id={DRAFT} claim={CLAIM}\n'

    @property
    def own(self):
        return next(row for row in self.releases if row['id'] == DRAFT)

    def download(self, identity, digest, directory):
        assert (identity, digest) == (ARCHIVE, DIGEST)
        self.download_called = True
        directory.mkdir()
        installer = directory / installer_name(SOURCE.version)
        installer.write_bytes(PAYLOAD)
        archive = directory / portable_name(SOURCE.version)
        archive.write_bytes(PORTABLE_PAYLOAD)
        checksum = hashlib.sha256(PAYLOAD).hexdigest() if not self.corrupt_checksum else 'b' * 64
        portable_checksum = hashlib.sha256(PORTABLE_PAYLOAD).hexdigest()
        portable_line = f'{portable_checksum}  {archive.name}\r\n'
        (directory / (archive.name + '.sha256')).write_bytes(portable_line.encode('ascii'))
        (directory / pub.CHECKSUM_NAME).write_bytes((f'{checksum}  {installer.name}\r\n' + portable_line).encode('ascii'))

    def mutate(self, method, endpoint, *, body=None, file=None):
        self.calls.append((method, endpoint))
        if method == 'POST' and endpoint == f'{API}/releases':
            assert body['tag_name'] == TAG and body['target_commitish'] == HEAD
            assert body['draft'] and body['generate_release_notes']
            self.add_owned(body['body'])
        elif method == 'POST' and endpoint.startswith(f'https://uploads.github.com/{API}/releases/{DRAFT}/assets?name='):
            assert endpoint.endswith(file.name) and file.is_file()
            self.own['assets'].append(self.asset_row(file.name, file.read_bytes(), False))
            self.on_upload()
        elif method == 'PATCH' and endpoint == f'{API}/releases/{DRAFT}':
            assert body == {'draft': False, 'make_latest': 'true'}
            self.mark_public()
            self.on_patch()
            if self.patch_mode == 'ambiguous':
                raise pub.MutationUnconfirmed('response lost')
            if self.patch_mode == 'unknown':
                self.get_release_unavailable = True
                raise pub.MutationUnconfirmed('response lost')
        else:
            raise AssertionError(f'Unexpected mutation: {method} {endpoint}')
        return deepcopy(self.own)

    def asset_row(self, name, data, public):
        names = [installer_name(SOURCE.version), portable_name(SOURCE.version),
                 portable_name(SOURCE.version) + '.sha256', pub.CHECKSUM_NAME]
        return {'id': 600 + names.index(name), 'name': name, 'state': 'uploaded',
                'size': len(data), 'digest': 'sha256:' + hashlib.sha256(data).hexdigest(),
                'browser_download_url': f"https://github.com/{REPOSITORY}/releases/download/{TAG if public else 'untagged-abc'}/{name}"}

    def add_owned(self, marker):
        row = release_row(DRAFT, TAG, draft=True)
        row.update(author=pub.BOT, name=pub.release_name(SOURCE), body=marker + '\n\nGenerated release notes', assets=[])
        self.releases.append(row)

    def mark_public(self):
        draft = self.own
        draft['draft'] = False
        draft['published_at'] = END
        for asset in draft['assets']:
            asset['browser_download_url'] = f"https://github.com/{REPOSITORY}/releases/download/{TAG}/{asset['name']}"


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.api = StubGitHub()
        self.sleep = patch.object(pub.time, 'sleep')
        self.sleep.start()
        self.addCleanup(self.sleep.stop)
        # Keep the local test output focused on assertions. Real publisher
        # logs must include the authenticated receipt.
        emit = patch.object(pub, 'print', create=True)
        self.emit = emit.start()
        self.addCleanup(emit.stop)

    @property
    def mutations(self):
        return [(method, endpoint) for method, endpoint in self.api.calls if method != 'GET']

    def publish(self):
        with tempfile.TemporaryDirectory() as root:
            return pub.publish(self.api, SOURCE, ISSUER, BLOB, Path(root) / 'installer', self.api.download)

    def owned_draft(self, uploads=(), *, public=False):
        with tempfile.TemporaryDirectory() as root:
            directory = Path(root) / 'installer'
            self.api.download(ARCHIVE, DIGEST, directory)
            assets = pub.read_payload(directory, SOURCE)
            provenance = {'repository': REPOSITORY_ID, 'tag': TAG, 'head': HEAD, 'tag_object': ANNOTATED,
                          'ci_workflow': pub.CI_ID, 'run': RUN, 'attempt': ATTEMPT, 'package_job': PACKAGE,
                          'artifact': ARCHIVE, 'artifact_digest': DIGEST, 'assets': [item.identity() for item in assets]}
            self.api.add_owned(pub.Claim(PREVIOUS, CLAIM).marker(provenance))
            for index in uploads:
                item = assets[index]
                self.api.own['assets'].append(self.api.asset_row(item.name, item.path.read_bytes(), public))
        if public:
            self.api.mark_public()

    def test_new_annotated_release_publication(self):
        self.assertIn('Publication confirmed', self.publish())
        self.assertFalse(self.api.own['draft'])
        methods = [method for method, _ in self.mutations]
        self.assertEqual(methods, ['POST', 'POST', 'POST', 'POST', 'POST', 'PATCH'])
        self.assertEqual({asset['name'] for asset in self.api.own['assets']},
                         {installer_name(SOURCE.version), portable_name(SOURCE.version),
                          portable_name(SOURCE.version) + '.sha256', pub.CHECKSUM_NAME})
        self.assertRegex(self.emit.call_args.args[0], rf'^GESHER_RELEASE_DRAFT id={DRAFT} claim=[0-9a-f]{{64}}$')
        patch_index = self.api.calls.index(('PATCH', f'{API}/releases/{DRAFT}'))
        self.assertEqual(self.api.calls[patch_index - 1], ('GET', f'{API}/git/ref/tags/{TAG}'))

    def test_product_history_release(self):
        # גשר המיתרים: קומיט מענף המוצר, שלא נמצא ב-main, מתפרסם.
        self.api.comparison['status'] = 'diverged'
        self.api.product_comparison = {'status': 'ahead', 'base_commit': {'sha': HEAD}, 'merge_base_commit': {'sha': HEAD}}
        self.assertIn('Publication confirmed', self.publish())
        self.assertFalse(self.api.own['draft'])
        self.assertEqual(self.api.own['name'], 'מיתר 0.2.1')

    def test_outside_main_and_product_or_missing_product_fails_without_mutation(self):
        for change in ('diverged', 'missing', 'other-base'):
            with self.subTest(change=change):
                self.api = StubGitHub()
                self.api.comparison['status'] = 'diverged'
                if change == 'missing':
                    self.api.product_exists = False
                elif change == 'other-base':
                    self.api.product_comparison = {'status': 'ahead', 'base_commit': {'sha': MAIN},
                                                   'merge_base_commit': {'sha': HEAD}}
                with self.assertRaises(pub.ReleaseError):
                    self.publish()
                self.assertFalse(self.api.download_called)
                self.assertEqual(self.mutations, [])

    def test_product_ci_definition_with_queued_tests(self):
        # גשר המיתרים: ה-ci.yml של המוצר כולל שלבים שה-PRs שבתור הוסיפו. הוא מתקבל רק כשהוא
        # זהה לזה שבראש product, ורק לקומיט מההיסטוריה של product.
        product_ahead = {'status': 'ahead', 'base_commit': {'sha': HEAD}, 'merge_base_commit': {'sha': HEAD}}
        for change in ('accepted', 'product-tip-differs', 'not-in-product'):
            with self.subTest(change=change):
                self.api = StubGitHub()
                self.api.comparison['status'] = 'diverged'
                self.api.ci_definition['sha'] = ANNOTATED
                self.api.product_ci_definition['sha'] = ANNOTATED
                self.api.product_comparison = deepcopy(product_ahead)
                if change == 'accepted':
                    self.assertIn('Publication confirmed', self.publish())
                    continue
                if change == 'product-tip-differs':
                    self.api.product_ci_definition['sha'] = BLOB
                else:
                    self.api.product_comparison['status'] = 'diverged'
                with self.assertRaises(pub.ReleaseError):
                    self.publish()
                self.assertFalse(self.api.download_called)
                self.assertEqual(self.mutations, [])

    def test_release_name_and_hebrew_install_notes(self):
        self.assertIn('Publication confirmed', self.publish())
        body = self.api.own['body']
        lines = body.splitlines()
        self.assertTrue(lines[0].startswith(pub.MARKER))
        self.assertEqual(sum(line.startswith(pub.MARKER) for line in lines), 1)
        self.assertIn(installer_name(SOURCE.version), body)
        self.assertIn('הפעל בכל זאת', body)
        self.assertIn(pub.CHECKSUM_NAME, body)
        self.assertIn(f'https://github.com/{REPOSITORY}/blob/main/docs/he/08-install-guide.md', body)

    def test_manual_dispatch_on_the_tag_publishes(self):
        # גשר המיתרים: ה-CI של גרסה רץ בהפעלה ידנית על התג.
        self.api.ci_run['event'] = 'workflow_dispatch'
        self.assertIn('Publication confirmed', self.publish())
        self.assertFalse(self.api.own['draft'])

    def test_release_notes_follow_the_install_instructions(self):
        # גשר המיתרים: "מה חדש" מ-tools/ci/release-notes/vX.Y.Z.md, אחרי הוראות ההתקנה.
        with tempfile.TemporaryDirectory() as root:
            notes = Path(root)
            (notes / 'v0.2.1.md').write_text('### מה חדש\n\n- סוכן עדכונים\n', encoding='utf-8')
            with patch.object(pub, 'RELEASE_NOTES', notes):
                intro = pub.release_intro(SOURCE)
                self.assertLess(intro.index('הפעל בכל זאת'), intro.index('### מה חדש'))
                (notes / 'v0.2.1.md').write_text(pub.MARKER + 'x -->', encoding='utf-8')
                with self.assertRaises(pub.ReleaseError):
                    pub.release_intro(SOURCE)
                (notes / 'v0.2.1.md').write_bytes(b'x' * (pub.MAX_RELEASE_NOTES + 1))
                with self.assertRaises(pub.ReleaseError):
                    pub.release_intro(SOURCE)
            with patch.object(pub, 'RELEASE_NOTES', notes / 'missing'):
                self.assertNotIn('### מה חדש', pub.release_intro(SOURCE))

    def test_lightweight_tag(self):
        self.api.tag['object'] = {'sha': HEAD, 'type': 'commit'}
        self.assertIn('Publication confirmed', self.publish())

    def test_untrusted_or_wrong_workflow_event_and_attempt_fail_without_mutation(self):
        for change in [{'run_attempt': 3}, {'event': 'schedule'}, {'event': 'pull_request'},
                       {'workflow_id': 45}, {'head_repository': {'id': 42, 'full_name': 'fork/gesher'}},
                       {'head_branch': 'main'}, {'conclusion': 'failure'}]:
            with self.subTest(change=change):
                self.api = StubGitHub()
                self.api.ci_run.update(change)
                with self.assertRaises((pub.ReleaseError, ValueError)):
                    self.publish()
                self.assertFalse(self.api.download_called)
                self.assertEqual(self.mutations, [])

    def test_source_workflow_path_accepts_only_bare_or_exact_verified_tag(self):
        for suffix in ('', f'@{TAG}', f'@refs/tags/{TAG}'):
            with self.subTest(suffix=suffix):
                run = dict(self.api.ci_run, path=pub.CI_PATH + suffix)
                self.assertEqual(pub.Source.from_run(run), SOURCE)
        for path in (pub.PUBLISH_PATH, f'{pub.CI_PATH}@main', f'{pub.CI_PATH}@refs/heads/{TAG}',
                     f'{pub.CI_PATH}@refs/tags/v0.2.2', f'{pub.CI_PATH}@{TAG}@{TAG}', f'{pub.CI_PATH}@'):
            with self.subTest(path=path), self.assertRaisesRegex(pub.ReleaseError, 'source workflow path'):
                pub.Source.from_run(dict(self.api.ci_run, path=path))

    def test_prior_publisher_workflow_path_accepts_only_bare_or_protected_main(self):
        for suffix in ('', '@main', '@refs/heads/main'):
            with self.subTest(suffix=suffix):
                self.api.issuer_path = pub.PUBLISH_PATH + suffix
                PREVIOUS.validate(self.api)
        for path in (pub.CI_PATH, f'{pub.PUBLISH_PATH}@refs/tags/main', f'{pub.PUBLISH_PATH}@release',
                     f'{pub.PUBLISH_PATH}@main@main', f'{pub.PUBLISH_PATH}@'):
            with self.subTest(path=path), self.assertRaisesRegex(pub.ReleaseError, 'canonical protected publisher'):
                self.api.issuer_path = path
                PREVIOUS.validate(self.api)

    def test_trusted_ci_blob_ancestry_and_real_tag_job_required(self):
        for change in ('different-yaml', 'off-main', 'skipped-tag-step', 'bad-required', 'old-package', 'stale-artifact'):
            with self.subTest(change=change):
                self.api = StubGitHub()
                if change == 'different-yaml':
                    self.api.ci_definition['sha'] = ANNOTATED
                elif change == 'off-main':
                    self.api.comparison['status'] = 'diverged'
                elif change == 'skipped-tag-step':
                    self.api.ci_jobs[0]['steps'][0]['conclusion'] = 'skipped'
                elif change == 'bad-required':
                    self.api.ci_jobs[1]['conclusion'] = 'failure'
                elif change == 'old-package':
                    self.api.ci_jobs[2]['run_attempt'] = 1
                else:
                    self.api.artifact['created_at'] = '2026-01-18T12:59:00Z'
                with self.assertRaises(pub.ReleaseError):
                    self.publish()
                self.assertFalse(self.api.download_called)
                self.assertEqual(self.mutations, [])

    def artifact(self, artifact_id, created_at, name=None):
        return dict(deepcopy(self.api.artifact), id=artifact_id, created_at=created_at,
                    name=name or pub.ARTIFACT_NAME)

    def test_rerun_inventory_is_paged_and_the_installer_is_from_the_exact_attempt(self):
        # גשר המיתרים: ריצה עם ארבעה ניסיונות. ‏artifacts של ניסיונות קודמים, גם מתקינים, לפני עבודת ה-package.
        self.api.extra_artifacts = [self.artifact(1000 + n, '2026-01-18T12:00:00Z', name=f'other-{n}') for n in range(180)]
        self.api.extra_artifacts += [self.artifact(2000 + n, f'2026-01-18T12:{10 + n}:00Z') for n in range(3)]
        _, artifact_id, digest = pub.confirm_producer(self.api, SOURCE)
        self.assertEqual((artifact_id, digest), (ARCHIVE, DIGEST))
        pages = [call for call in self.api.calls if '/artifacts?' in call[1]]
        self.assertEqual(len(pages), 2)

    def test_two_installers_of_the_exact_attempt_are_ambiguous(self):
        self.api.extra_artifacts = [self.artifact(3000, CREATED)]
        with self.assertRaisesRegex(pub.ReleaseError, 'Missing or ambiguous installer artifact'):
            pub.confirm_producer(self.api, SOURCE)

    def test_incomplete_artifact_inventory_fails_without_mutation(self):
        self.api.extra_artifacts = [self.artifact(1000 + n, CREATED, name=f'other-{n}') for n in range(150)]
        for total in (300, 120):
            with self.subTest(total=total):
                self.api.artifact_total = total
                with self.assertRaisesRegex(pub.ReleaseError, 'Incomplete artifact inventory'):
                    self.publish()
                self.assertFalse(self.api.download_called)
                self.assertEqual(self.mutations, [])

    def test_manual_publication_reads_the_ci_run_from_github(self):
        event = {'repository': {'id': REPOSITORY_ID, 'full_name': REPOSITORY, 'default_branch': 'main'}}
        environ = {'GITHUB_EVENT_NAME': 'workflow_dispatch', 'PUBLISH_CI_RUN_ID': str(RUN)}
        self.assertEqual(pub.Source.from_run(pub.source_run(self.api, environ, event)), SOURCE)
        for run_id in ('', '0', '12a', ' 101', '101 ', '-101', '1' * 21):
            with self.subTest(run_id=run_id), self.assertRaisesRegex(pub.ReleaseError, 'needs the CI run id'):
                pub.source_run(self.api, dict(environ, PUBLISH_CI_RUN_ID=run_id), event)
        fork = {'repository': {'id': 42, 'full_name': 'fork/gesher', 'default_branch': 'main'}}
        with self.assertRaisesRegex(pub.ReleaseError, 'canonical repository'):
            pub.source_run(self.api, environ, fork)
        failed = dict(self.api.ci_run, conclusion='failure')
        self.api.ci_run = failed
        with self.assertRaises(pub.ReleaseError):
            pub.Source.from_run(pub.source_run(self.api, environ, event))

    def test_manual_publisher_run_is_a_canonical_issuer(self):
        self.api.issuer_event = 'workflow_dispatch'
        PREVIOUS.validate(self.api)
        for event in ('push', 'schedule', 'pull_request_target'):
            with self.subTest(event=event), self.assertRaisesRegex(pub.ReleaseError, 'canonical protected publisher'):
                self.api.issuer_event = event
                PREVIOUS.validate(self.api)

    def test_manual_or_forged_draft_is_untouched(self):
        self.api.releases.append(release_row(DRAFT, TAG, draft=True))
        with self.assertRaisesRegex(pub.ReleaseError, 'publisher marker'):
            self.publish()
        self.assertEqual(self.mutations, [])
        self.api = StubGitHub()
        self.owned_draft()
        self.api.job_log = lambda _: f'GESHER_RELEASE_DRAFT id={DRAFT + 1} claim={CLAIM}\n'
        with self.assertRaisesRegex(pub.ReleaseError, 'authenticated publisher receipt'):
            self.publish()
        self.assertEqual(self.mutations, [])

    def test_resume_only_uploads_missing_assets(self):
        self.owned_draft((0,))
        self.assertIn('Publication confirmed', self.publish())
        self.assertEqual(self.mutations, [
            ('POST', f'https://uploads.github.com/{API}/releases/{DRAFT}/assets?name={portable_name(SOURCE.version)}'),
            ('POST', f'https://uploads.github.com/{API}/releases/{DRAFT}/assets?name={portable_name(SOURCE.version)}.sha256'),
            ('POST', f'https://uploads.github.com/{API}/releases/{DRAFT}/assets?name=SHA256SUMS.txt'),
            ('PATCH', f'{API}/releases/{DRAFT}'),
        ])

    def test_mismatching_existing_asset_or_provenance_is_untouched(self):
        self.owned_draft((0,))
        self.api.own['assets'][0]['digest'] = DIGEST
        with self.assertRaisesRegex(pub.ReleaseError, 'does not match'):
            self.publish()
        self.assertEqual(self.mutations, [])
        self.api = StubGitHub()
        self.owned_draft()
        self.api.own['body'] = self.api.own['body'].replace('"attempt":2', '"attempt":1')
        with self.assertRaisesRegex(pub.ReleaseError, 'does not match'):
            self.publish()
        self.assertEqual(self.mutations, [])

    def test_payload_checksum_failure_leaves_releases_untouched(self):
        self.api.corrupt_checksum = True
        with self.assertRaisesRegex(pub.ReleaseError, 'does not match'):
            self.publish()
        self.assertEqual(self.mutations, [])

    def test_portable_payload_failures_leave_releases_untouched(self):
        for problem in ('missing', 'bytes', 'individual-checksum', 'combined-checksum', 'wrong-version', 'extra'):
            with self.subTest(problem=problem):
                self.api = StubGitHub()
                download = self.api.download
                def corrupt(identity, digest, directory):
                    download(identity, digest, directory)
                    archive = directory / portable_name(SOURCE.version)
                    if problem == 'missing':
                        archive.unlink()
                    elif problem == 'bytes':
                        archive.write_bytes(PORTABLE_PAYLOAD + b'changed')
                    elif problem == 'individual-checksum':
                        (directory / (archive.name + '.sha256')).write_bytes(b'wrong\n')
                    elif problem == 'combined-checksum':
                        checksum = directory / pub.CHECKSUM_NAME
                        checksum.write_bytes(checksum.read_bytes().splitlines()[0] + b'\n')
                    elif problem == 'wrong-version':
                        archive.rename(directory / 'gesher-0.2.2-portable.zip')
                    else:
                        (directory / 'unverified.zip').write_bytes(PORTABLE_PAYLOAD)
                self.api.download = corrupt
                with self.assertRaises(pub.ReleaseError):
                    self.publish()
                self.assertEqual(self.mutations, [])

    def test_tag_moved_or_deleted_after_upload_leaves_draft(self):
        for updated in (None, {'ref': f'refs/tags/{TAG}', 'object': {'type': 'commit', 'sha': MAIN}}):
            with self.subTest(updated=updated):
                self.api = StubGitHub()
                self.api.on_upload = lambda: setattr(self.api, 'tag', updated)
                with self.assertRaises((GitHubReadError, pub.ReleaseError)):
                    self.publish()
                self.assertTrue(self.api.own['draft'])
                self.assertNotIn('PATCH', [method for method, _ in self.mutations])

    def test_newer_release_during_upload_prevents_publication(self):
        self.api.on_upload = lambda: self.api.releases.append(release_row(901 + len(self.api.releases), 'v0.3.0'))
        with self.assertRaisesRegex(pub.ReleaseError, 'newer'):
            self.publish()
        self.assertTrue(self.api.own['draft'])
        self.assertNotIn('PATCH', [method for method, _ in self.mutations])

    def test_ambiguous_patch_reconciles_exact_release_independent_of_latest(self):
        self.api.patch_mode = 'ambiguous'
        self.api.on_patch = lambda: self.api.releases.append(release_row(901, 'v0.3.0'))
        self.assertIn('Publication confirmed', self.publish())
        self.assertFalse(self.api.own['draft'])
        self.assertEqual([method for method, _ in self.mutations].count('PATCH'), 1)

    def test_ambiguous_patch_with_unavailable_postflight_reports_uncertainty(self):
        self.api.patch_mode = 'unknown'
        with self.assertRaisesRegex(pub.ReleaseError, f'Publication outcome uncertain after PATCH for release {DRAFT}'):
            self.publish()
        self.assertFalse(self.api.own['draft'])
        self.assertEqual([method for method, _ in self.mutations].count('PATCH'), 1)

    def test_public_mismatching_assets_report_actual_publication(self):
        self.api.on_patch = lambda: self.api.own['assets'][0].update(digest=DIGEST)
        with self.assertRaisesRegex(pub.PublicAssetsUnconfirmed, f'Release {DRAFT} is public'):
            self.publish()
        self.assertFalse(self.api.own['draft'])
        self.assertEqual([method for method, _ in self.mutations].count('PATCH'), 1)

    def test_tag_change_after_patch_reports_actual_publication(self):
        self.api.on_patch = lambda: self.api.tag.update(object={'type': 'commit', 'sha': MAIN})
        with self.assertRaisesRegex(pub.ReleaseError, f'Release {DRAFT} was published, but its tag'):
            self.publish()
        self.assertFalse(self.api.own['draft'])

    def test_exact_published_release_is_idempotent_after_newer_release(self):
        self.owned_draft((0, 1, 2, 3), public=True)
        self.api.releases.append(release_row(901, 'v0.3.0'))
        self.assertIn('Publication already confirmed', self.publish())
        self.assertEqual(self.mutations, [])


if __name__ == '__main__':
    unittest.main()
