"""בונה את ענף המוצר (product): הענף הראשי שלנו, ועוד ה-PRs שעוד לא אושרו ב-upstream.

למה ענף נפרד: upstream ממזג PRs אחרי דחיסה לקומיט אחד (squash), ולעתים מתקן
אותם לפני כן. PR שלקחנו מוקדם ויושב בענף הראשי שלנו מגיע אלינו פעמיים, בשתי
גרסאות, ומתנגש. ב-25.11.2026 זה יצר 27 קבצים בהתנגשות. לכן הענף הראשי נשאר
upstream ועוד מה שאנחנו כתבנו, וה-PRs הפתוחים נכנסים רק לענף המוצר. הענף נבנה
מחדש על הענף הראשי העדכני בכל סנכרון, ו-PR ש-upstream כבר מיזג יורד מהבנייה לבד.

התור: tools/integration/product-queue.tsv. כל שורה היא פריט, לפי סדר המיזוג.
עמודות, מופרדות בטאב:
  מזהה    שם קצר וקבוע, למשל pr-464
  מקור    remote:ref שממנו מושכים, למשל upstream:refs/pull/464/head
  SHA     הקומיט הנעוץ שנכנס לבנייה (40 תווים)
  PRs     מספרי ה-PRs ב-upstream שהפריט מכיל, מופרדים בפסיק, או -
  גל      מספר הגל במרשם
  תיאור   טקסט חופשי

כשפריט מתנגש, לא פותרים בתוך ענף המוצר. יוצרים ענף נושא (topic/<מזהה>) שבו
הפריט מעודכן על upstream העדכני והתנגשות נפתרת, ונועצים אותו בתור. כך הפתרון
הוא קומיט רגיל: הוא עובר ביקורת ונשמר לבנייה הבאה. התנגשות שכולה בקבצים
שמופקים מ-tools/i18n/messages.json נפתרת לבד, בהפקה מחדש.

ענף המוצר מתקדם בלי לדרוס היסטוריה: כל בנייה מאושרת נרשמת כקומיט שהעץ שלו הוא
הבנייה החדשה, וההורים שלו הם ענף המוצר הקודם והבנייה החדשה.

שימוש:
  python3 tools/integration/build_product.py --check          # סימולציה, בלי לשנות כלום
  python3 tools/integration/build_product.py --fetch          # מושך את כל המקורות שבתור
  python3 tools/integration/build_product.py                  # בונה את product-candidate
  python3 tools/integration/build_product.py --topic ID       # ענף נושא לפריט שמתנגש
  python3 tools/integration/build_product.py --pin ID         # נועץ בתור את ענף הנושא
  python3 tools/integration/build_product.py --promote        # מקדם את product לבנייה
אפשרויות:
  --base REF       הבסיס לבנייה (ברירת מחדל: main)
  --upstream REF   הענף של upstream, לזיהוי מה שכבר מוזג (ברירת מחדל: upstream/main)
  --onto-candidate עם --topic: ממזג לענף הנושא את product-candidate במקום את upstream,
                   כשההתנגשות היא מול PR אחר בתור ולא מול upstream
  --trailers FILE  שורות שנוספות לסוף כל הודעת קומיט שהכלי יוצר
  --skip-conflicts בבנייה: פריט שמתנגש מדולג ומסומן "ממתין", במקום לעצור את הבנייה.
                   מתאים לפריט שהתורם עוד לא עדכן על upstream העדכני
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

QUEUE = Path("tools/integration/product-queue.tsv")
CANDIDATE = "product-candidate"
PRODUCT = "product"
COLUMNS = ("id", "source", "sha", "prs", "wave", "desc")
SUBJECT_PR = re.compile(r"\(#(\d+)\)\s*$")
MERGE_PR = re.compile(r"^Merge pull request #(\d+) ")


class Failure(Exception):
    pass


def git(*args, cwd=None, check=True):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise Failure(f"git {' '.join(args)} נכשל:\n{r.stderr.strip()}")
    return r


def out(*args, cwd=None):
    return git(*args, cwd=cwd).stdout.strip()


def repo_root():
    return Path(out("rev-parse", "--show-toplevel"))


# ---------- התור ----------

def load_queue(root):
    path = root / QUEUE
    header, items = [], []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            if not items:
                header.append(line)
            continue
        cells = line.split("\t")
        if len(cells) != len(COLUMNS):
            raise Failure(f"{QUEUE}:{n}: צריך {len(COLUMNS)} עמודות מופרדות בטאב, נמצאו {len(cells)}")
        item = dict(zip(COLUMNS, cells))
        if not re.fullmatch(r"[0-9a-f]{40}", item["sha"]):
            raise Failure(f"{QUEUE}:{n}: ה-SHA של {item['id']} חייב להיות 40 תווים הקסדצימליים")
        if ":" not in item["source"]:
            raise Failure(f"{QUEUE}:{n}: המקור של {item['id']} צריך להיות remote:ref")
        item["pr_list"] = [] if item["prs"] == "-" else [int(p) for p in item["prs"].split(",")]
        items.append(item)
    ids = [i["id"] for i in items]
    if len(ids) != len(set(ids)):
        raise Failure(f"{QUEUE}: יש מזהה שמופיע יותר מפעם אחת")
    return header, items


def save_queue(root, header, items):
    lines = header + ["\t".join(i[c] for c in COLUMNS) for i in items]
    (root / QUEUE).write_text("\n".join(lines) + "\n", encoding="utf-8")


def find(items, item_id):
    for item in items:
        if item["id"] == item_id:
            return item
    raise Failure(f"אין בתור פריט בשם {item_id}")


# ---------- מה כבר נכנס ----------

def merged_prs(upstream):
    """מספרי ה-PRs ש-upstream כבר מיזג לענף הראשי שלו, לפי כותרות הקומיטים."""
    merged = set()
    for subject in out("log", "--first-parent", "--format=%s", upstream).splitlines():
        m = SUBJECT_PR.search(subject) or MERGE_PR.match(subject)
        if m:
            merged.add(int(m.group(1)))
    return merged


def is_ancestor(a, b, cwd=None):
    return git("merge-base", "--is-ancestor", a, b, cwd=cwd, check=False).returncode == 0


def has_commit(sha):
    return git("cat-file", "-e", sha + "^{commit}", check=False).returncode == 0


def classify(item, merged, head, cwd=None):
    """מחזיר (מצב, הסבר). מצב: skip, warn או merge."""
    prs = item["pr_list"]
    done = [p for p in prs if p in merged]
    if prs and len(done) == len(prs):
        return "skip", "upstream כבר מיזג את " + ", ".join(f"#{p}" for p in prs)
    if is_ancestor(item["sha"], head, cwd):
        return "skip", "כבר נמצא בבסיס"
    if done:
        return "warn", ("upstream מיזג רק חלק מהתוכן (" + ", ".join(f"#{p}" for p in done) +
                        "). צריך לבדוק ביד אם הפריט עדיין נחוץ")
    return "merge", ""


def stale_note(item):
    """אזהרה כשהמקור התקדם מאז הנעיצה (התורם עדכן את ה-PR)."""
    remote, ref = item["source"].split(":", 1)
    local = f"refs/product-sources/{item['id']}"
    r = git("rev-parse", "--verify", "-q", local, check=False)
    if r.returncode == 0 and r.stdout.strip() != item["sha"]:
        return f"למקור יש גרסה חדשה יותר ({r.stdout.strip()[:12]}) מהנעוצה. כדאי לבדוק ולנעוץ מחדש"
    return ""


# ---------- קבצים מופקים ----------

def generated_files(cwd):
    code = ("import sys; sys.path.insert(0, 'tools/i18n'); import generate; "
            "print('\\n'.join(str(p.relative_to(generate.ROOT)) for p in generate.outputs()))")
    r = subprocess.run([sys.executable, "-c", code], cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return set(r.stdout.split())


def regenerate(cwd):
    r = subprocess.run([sys.executable, "tools/i18n/generate.py"], cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise Failure("tools/i18n/generate.py נכשל:\n" + (r.stderr or r.stdout).strip())


def i18n_stale(cwd):
    r = subprocess.run([sys.executable, "tools/i18n/generate.py", "--check"], cwd=cwd,
                       capture_output=True, text=True)
    return r.returncode != 0


# ---------- הודעות קומיט ----------

def message(subject, body, trailers):
    parts = [subject]
    if body:
        parts += ["", body]
    if trailers:
        parts += ["", trailers]
    return "\n".join(parts) + "\n"


def write_message(text):
    f = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False)
    f.write(text)
    f.close()
    return f.name


def commit_with(cwd, text, *args):
    path = write_message(text)
    try:
        git(*args, "-F", path, cwd=cwd)
    finally:
        Path(path).unlink()


# ---------- פעולות ----------

def do_fetch(items):
    for item in items:
        remote, ref = item["source"].split(":", 1)
        local = f"refs/product-sources/{item['id']}"
        r = git("fetch", "-q", remote, f"+{ref}:{local}", check=False)
        state = "נמשך" if r.returncode == 0 else "לא נמשך: " + r.stderr.strip().splitlines()[-1]
        if r.returncode == 0 and not has_commit(item["sha"]):
            git("fetch", "-q", remote, item["sha"], check=False)
        pinned = "קיים" if has_commit(item["sha"]) else "חסר"
        print(f"  {item['id']}: {state}. הקומיט הנעוץ {item['sha'][:12]}: {pinned}")
        note = stale_note(item)
        if note:
            print(f"      {note}")


def do_check(items, base, upstream):
    merged = merged_prs(upstream)
    head = out("rev-parse", base)
    clean = True
    for item in items:
        if not has_commit(item["sha"]):
            print(f"  {item['id']}: הקומיט הנעוץ חסר מקומית. הריצו קודם --fetch")
            clean = False
            continue
        state, why = classify(item, merged, head)
        if state == "skip":
            print(f"  {item['id']}: דולג. {why}")
            continue
        if state == "warn":
            print(f"  {item['id']}: אזהרה. {why}")
        r = git("merge-tree", "--write-tree", "--name-only", "--no-messages", head, item["sha"], check=False)
        lines = r.stdout.split()
        tree = lines[0]
        note = stale_note(item)
        if r.returncode == 0:
            print(f"  {item['id']}: נכנס נקי")
            head = out("commit-tree", tree, "-p", head, "-p", item["sha"], "-m", "סימולציה")
        else:
            files = lines[1:]
            print(f"  {item['id']}: התנגשות ב-{len(files)} קבצים (הפריטים הבאים נבדקים בלעדיו):")
            for f in files:
                print(f"      {f}")
            clean = False
        if note:
            print(f"      {note}")
    print("הסימולציה נקייה." if clean else "יש פריטים שדורשים טיפול (ענף נושא, ‏--topic).")
    return clean


def do_build(root, items, base, upstream, trailers, skip_conflicts=False):
    merged = merged_prs(upstream)
    if not all(has_commit(i["sha"]) for i in items):
        raise Failure("חסרים קומיטים נעוצים. הריצו קודם --fetch")
    wt = Path(tempfile.mkdtemp(prefix="gesher-product-"))
    git("worktree", "add", "-q", "-B", CANDIDATE, str(wt), base)
    report = []
    waiting = []
    try:
        for item in items:
            head = out("rev-parse", "HEAD", cwd=wt)
            state, why = classify(item, merged, head, cwd=wt)
            if state == "skip":
                report.append(f"דולג: {item['id']}. {why}")
                continue
            if state == "warn":
                report.append(f"אזהרה: {item['id']}. {why}")
            prs = ", ".join(f"#{p}" for p in item["pr_list"]) or "אין"
            text = message(f"מיזוג {item['id']} לענף המוצר (גל {item['wave']}): {item['desc']}",
                           f"מקור: {item['source']} @ {item['sha'][:12]}\nPRs ב-upstream: {prs}", trailers)
            path = write_message(text)
            try:
                r = git("merge", "--no-ff", "-q", "-F", path, item["sha"], cwd=wt, check=False)
            finally:
                Path(path).unlink()
            if r.returncode != 0:
                conflicts = set(out("diff", "--name-only", "--diff-filter=U", cwd=wt).split())
                generated = generated_files(wt) or set()
                if conflicts and conflicts <= generated:
                    git("checkout", "--ours", "--", *conflicts, cwd=wt)
                    regenerate(wt)
                    git("add", "--", *generated, cwd=wt)
                    git("commit", "-q", "--no-edit", cwd=wt)
                    report.append(f"נכנס: {item['id']} (התנגשות בקבצים מופקים נפתרה בהפקה מחדש)")
                    continue
                git("merge", "--abort", cwd=wt, check=False)
                if skip_conflicts and conflicts:
                    waiting.append(item["id"])
                    report.append(f"ממתין: {item['id']} מתנגש ב-{len(conflicts)} קבצים, ולא נכנס לבנייה הזו")
                    continue
                lines = [f"  {f}" for f in sorted(conflicts)] or ["  " + r.stderr.strip()]
                raise Failure(f"{item['id']} מתנגש בבנייה:\n" + "\n".join(lines) +
                              f"\nפתרון: python3 {QUEUE.parent}/build_product.py --topic {item['id']}")
            if i18n_stale(wt):
                regenerate(wt)
                git("add", "-A", cwd=wt)
                commit_with(wt, message(f"הפקה מחדש של קבצי השפה אחרי מיזוג {item['id']}", "", trailers),
                            "commit", "-q")
                report.append(f"נכנס: {item['id']} (ועוד הפקה מחדש של קבצי השפה)")
            else:
                report.append(f"נכנס: {item['id']}")
        r = subprocess.run([sys.executable, "-I", "tools/integration/retarget_repository.py", "--check"],
                           cwd=wt, capture_output=True, text=True)
        report.append("מסלול המוצר: " + (r.stdout.strip().splitlines() or ["?"])[-1])
        if r.returncode != 0:
            raise Failure("בדיקת הכיוון לריפו שלנו נכשלה:\n" + r.stdout.strip())
    finally:
        git("worktree", "remove", "--force", str(wt), check=False)
        shutil.rmtree(wt, ignore_errors=True)
    print(f"נבנה {CANDIDATE} ({out('rev-parse', '--short', CANDIDATE)}) על {base}:")
    for line in report:
        print("  " + line)
    if waiting:
        print(f"ממתינים ({len(waiting)}): " + ", ".join(waiting) +
              ". כשהתורם יעדכן: --fetch ונעיצה מחדש. אחרת: --topic.")


def do_topic(items, item_id, upstream, onto_candidate):
    item = find(items, item_id)
    if git("status", "--porcelain").stdout.strip():
        raise Failure("עץ העבודה לא נקי. שמרו או בטלו את השינויים קודם")
    branch = f"topic/{item_id}"
    exists = git("rev-parse", "--verify", "-q", branch, check=False).returncode == 0
    git("checkout", "-q", branch) if exists else git("checkout", "-q", "-b", branch, item["sha"])
    other = CANDIDATE if onto_candidate else upstream
    r = git("merge", "--no-ff", "--no-commit", other, check=False)
    if r.returncode == 0:
        print(f"{other} נכנס ל-{branch} בלי התנגשות. בדקו, צרו קומיט, ואז --pin {item_id}")
    else:
        files = out("diff", "--name-only", "--diff-filter=U").split()
        print(f"{branch}: יש לפתור {len(files)} קבצים:")
        for f in files:
            print(f"  {f}")
        print(f"אחרי הפתרון: git add, ‏git commit, ואז --pin {item_id}")


def do_pin(root, header, items, item_id):
    item = find(items, item_id)
    branch = f"topic/{item_id}"
    sha = out("rev-parse", branch)
    if not is_ancestor(item["sha"], sha):
        raise Failure(f"{branch} לא מכיל את הקומיט הנעוץ הקודם של {item_id}")
    item["source"] = f"origin:refs/heads/{branch}"
    item["sha"] = sha
    save_queue(root, header, items)
    print(f"{item_id} נעוץ עכשיו ל-{branch} @ {sha[:12]}.")
    print(f"לא לשכוח: git push origin {branch}, וקומיט של {QUEUE} בענף הראשי.")


def do_promote(trailers):
    cand = out("rev-parse", CANDIDATE)
    old = git("rev-parse", "--verify", "-q", PRODUCT, check=False)
    if old.returncode != 0:
        old = git("rev-parse", "--verify", "-q", f"origin/{PRODUCT}", check=False)
    if old.returncode != 0:
        git("branch", "-f", PRODUCT, cand)
        print(f"{PRODUCT} נוצר מ-{CANDIDATE} ({cand[:12]}).")
        return
    old = old.stdout.strip()
    if is_ancestor(old, cand):
        git("branch", "-f", PRODUCT, cand)
        print(f"{PRODUCT} קודם ל-{cand[:12]} (המשך ישיר).")
        return
    tree = out("rev-parse", cand + "^{tree}")
    text = message("בניית ענף המוצר מחדש",
                   f"העץ הוא {CANDIDATE} ({cand[:12]}). ההורה הראשון הוא {PRODUCT} הקודם,\n"
                   f"כדי שההיסטוריה תישמר בלי דריסה.", trailers)
    path = write_message(text)
    try:
        new = out("commit-tree", tree, "-p", old, "-p", cand, "-F", path)
    finally:
        Path(path).unlink()
    git("branch", "-f", PRODUCT, new)
    print(f"{PRODUCT} קודם ל-{new[:12]}: העץ של {CANDIDATE}, אחרי {old[:12]}.")


def main():
    p = argparse.ArgumentParser(description="בונה את ענף המוצר מתור ה-PRs")
    p.add_argument("--check", action="store_true")
    p.add_argument("--fetch", action="store_true")
    p.add_argument("--topic")
    p.add_argument("--pin")
    p.add_argument("--promote", action="store_true")
    p.add_argument("--onto-candidate", action="store_true")
    p.add_argument("--skip-conflicts", action="store_true")
    p.add_argument("--base", default="main")
    p.add_argument("--upstream", default="upstream/main")
    p.add_argument("--trailers")
    a = p.parse_args()
    trailers = Path(a.trailers).read_text(encoding="utf-8").strip() if a.trailers else ""
    try:
        root = repo_root()
        header, items = load_queue(root)
        if a.fetch:
            do_fetch(items)
        elif a.check:
            sys.exit(0 if do_check(items, a.base, a.upstream) else 1)
        elif a.topic:
            do_topic(items, a.topic, a.upstream, a.onto_candidate)
        elif a.pin:
            do_pin(root, header, items, a.pin)
        elif a.promote:
            do_promote(trailers)
        else:
            do_build(root, items, a.base, a.upstream, trailers, a.skip_conflicts)
    except Failure as e:
        print(f"שגיאה: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
