# Account authenticator request admission — NATIVE-10, part A

This change addresses the AccountManager asynchronous authenticator owner in
[#178](https://github.com/gesher-runtime/gesher/issues/178). It is a first account
sub-round, not completion of NATIVE-10 or of all AccountManager resource owners.
The comparison base is `638e19b4a6c109ec8881ba90a94d64b1817fc095`.

## Observable behavior and contract

Previously, asynchronous account operations used `newCachedThreadPool`. A burst
could create a worker for every blocking authenticator or application response.
Returning an initial login Intent also left an independently timed continuation.

`AccountRequests` now admits an operation before it copies options/features,
consumes an opaque one-shot session handle, or queues a worker. Caller identity
and public permission/argument checks still precede that admission. Rejection
uses `AccountManager.ERROR_CODE_REMOTE_EXCEPTION` once; it does not manufacture
an empty success result. A rejected `finishSessionAsUser` retains its handle for
a later attempt. Once admitted, consuming that handle keeps its existing
one-shot semantics, including failure after consumption.

The ordinary authenticator, login Activity, token validation, visibility,
credential consent and durable account-state paths still run. This change adds
no package-specific success behavior, replacement credentials, or fixture input
to production. Login Intent component/selector/grant checks operate on an owned
Intent snapshot before completion queuing, preventing a local authenticator
from mutating those checked fields through its original object.

The timeout is 15 minutes of Android uptime, including admission, input
preparation and queue time. The pinned Android
[AccountManagerService](https://github.com/aosp-mirror/platform_frameworks_base/blob/45034f0663f960d9ee5fb0a101a4732b71f6e2f4/services/core/java/com/android/server/accounts/AccountManagerService.java)
uses that session budget and reports remote-service failure for timeout.
[AccountManager error constants](https://github.com/aosp-mirror/platform_frameworks_base/blob/45034f0663f960d9ee5fb0a101a4732b71f6e2f4/core/java/android/accounts/AccountManager.java)
provide the existing remote-failure, cancellation and invalid-response results.
The queue and admission design is Gesher's implementation choice; those specific
capacity values are not presented as an Android platform requirement.

## Bounds and ownership

| Owned resource | Limit / retirement rule |
| --- | --- |
| Admitted requests | 256 globally, 64 per captured caller package/code identity |
| Blocking operation workers | 32, with a queue bounded by total admission |
| Application completion workers | 4; one scheduled/running drain per admitted request |
| Outbound results per request | 8 queued/executing results, plus one terminal control error |
| Initial authenticator results | 8 before continuation registration; inbound copies/validation serialize before retaining additional payloads |
| Backend identity guards | 32 per request, deduplicated by key; the first captured identity is retained |
| Deadline/retry scheduler | One worker, at most one deadline and one dispatcher retry per admitted request |
| Idle pool lifetime | Operation, completion and timer workers allow 60-second core-thread retirement |

These are owner/envelope bounds, **not a byte limit on arbitrary Bundles, account
lists, strings or the process working set**. A copied Bundle retains its normal
Android value semantics. The initial and outbound response limits are separate;
they must not be added to an unsupported claim of eight total objects in memory.

A ticket remains charged through input preparation, queued/running operation,
interactive Answer lifetime, active service-connection IPC, executing incoming
authenticator callbacks, outbound callbacks, and response-Binder unlink. A
timeout, caller death or package retirement can close the public session without
pretending an uninterruptible call has returned. Those active references keep the
ticket charged until the real call exits.

Deadline processing and short Answer cancellation hooks do not execute
application callbacks or acquire the Answer delivery lock. A stalled validator
therefore cannot stop the shared deadline owner. Bundle copying also occurs
outside the Answer state monitor used by cancellation. Inbound concurrent foreign
callers wait at their existing call boundary before a copied result is retained;
the service does not create another worker or internal result queue for them.

Before starting queued work, and immediately before outbound delivery, the owner
checks the captured caller. Successful results additionally recheck their
captured authenticator dependency. Token replies, including cache hits, recheck
current account ownership, visibility and credential authorization. This keeps
completion queuing from extending a previously validated access decision across
retirement. Original authenticator error codes are preserved; backend-success
guards are not used to rewrite an existing error.

Accepted login results keep FIFO order ahead of a later timeout/overflow error.
Caller retirement can suppress queued sensitive results and replace them with a
single cancellation. Dead clients receive no callback. The owner catches a
throwing application response so it does not kill the completion lane or replay
a terminal response. Timer startup failure rolls back admission before input
copy; operation-worker startup failure publishes one error while the copied
request remains owned. Completion-worker startup failures retain their queue
entry and retry from the existing timer. No progress promise can survive an
operating system that cannot start any worker.

### Capacity is not a universal fairness guarantee

The caller quota leaves admission slots for another caller. It does not reserve
an execution or completion thread per caller. One caller can occupy all 32
operation workers with uninterruptible IPC, or all four response workers with
blocked local callbacks. Other accepted work then waits for real capacity;
deadline state can still become terminal, while response publication itself
waits for a completion worker. The service reports no false success or reclaimed
capacity in that condition. Overload errors run synchronously on the API caller,
as existing immediate service-unavailable errors do, and create no hidden
rejection queue. An external caller can block its own thread inside that error.

## Verification

The host gate compiles the **whole submitted** `AccountRequests.java` and
`AccountManagerService.java`, using real cached Android framework/core classes.
It uses the existing `tests/account-session/framework_host.c` adapter for
identity, clocks and allocation boundaries. Blocked/failing authenticators and
application responses are explicitly local test endpoints. Production Java
methods are not replaced by a second implementation of admission.

The focused suite passed **283 checks** on 22 November 2026. It covers sequential
bursts of 1/32/256/1024, 32 simultaneous producers submitting 1024 operations,
per-caller admission, blocked completion retention, interactive and active-IPC
leases, queued expiry before backend entry, active timeout, caller death/removal,
result overflow/order, timer/worker/dispatcher startup failure, callback
reentrancy and exceptions, preparation cancellation, caller/backend revalidation,
one-shot finish rejection, and the full service's Answer lifetimes.

In the incoming-callback regression, the initial operation worker has already
returned. A later authenticator callback stalls in validation, then timeout or
authenticator package removal closes its Answer. The deadline/removal call
returns; the request remains admitted until validation exits. Another case
expires a request before Answer construction and verifies the returned lease is
retired without reviving the canceled session.

| Repeated production-source check | Result |
| --- | --- |
| Existing Answer lifetime contracts | 41 passed |
| Existing Answer timeout contracts | 249 passed |
| Existing account retirement contracts | 29 passed |
| Explicit removal rollback / unchanged / update / reinstall | 4 / 7 / 7 / 5 passed |
| Account/package lock ordering, with and without manifest receivers | Both passed |
| Existing GMS setup lifecycle | 28 passed |
| `app/build.sh`, normal app Java and D8 path | Passed |
| Complete `tests/dex-services/build.sh` Java and D8 path | Passed |

The original full-service negative control compiles the service from the exact
base commit, then invokes its real `getAccountsByFeatures` entry with 128 blocked
responses. It fails the new assertion with **128 blocked callback workers and
zero overload errors**. The submitted service observes **four blocked callback
workers and 64 overload errors** for the same caller. This is behavior-based
evidence; it does not infer the result from a source-text search. Burst samples
are retained in [account-admission-host.csv](account-admission-host.csv).

### Reproduce the required host gate

```sh
python3 tools/test_account_session_lifetime.py \
  --java-home "$JDK" --framework-classes "$FRAMEWORK_CLASSES" \
  --core-classes "$CORE_CLASSES" --app-classes "$APP_CLASSES" \
  --apksig-jar "$APKSIG_JAR"
```

This existing gate now calls `tools/test_account_request_admission.py`. The
immutable framework workflow controller already calls the gate against the
submitted source checkout; no branch-local workflow edit or controller-pin
change is needed to reach the new assertions. The separate sync gate also
already includes the account-lifetime entry point.

For the expected-failing original-source control:

```sh
python3 tools/test_account_request_admission.py \
  --java-home "$JDK" --framework-classes "$FRAMEWORK_CLASSES" \
  --core-classes "$CORE_CLASSES" --app-classes "$APP_CLASSES" \
  --apksig-jar "$APKSIG_JAR" \
  --source-ref 638e19b4a6c109ec8881ba90a94d64b1817fc095
```

### Evidence limits and remaining account work

The dependency framework classes were produced by CI run `44715261143` at
`8e9d442ac7617d82d53f980e58806b107ce26e0f` on 20 November. Local app generation uses
the retained pinned AOSP source subset and cached Android core inputs. These
builds are not a fresh complete Android platform build. Host output contains the
existing declared unavailable Android native resource/cache boundaries; it does
not establish Windows ART, remote Binder, DPAPI, physical UI, eight-hour soak,
process RSS/CPU, or a latency/throughput improvement. The unchanged Windows
microG-security gate still needs to run on the published head with its real
authenticator/login, credential-grant, visibility, removal and restart tests.

The following owners remain separate, explicitly open work:

- Durable account-change/visibility notifications: `mCalls` and `mChanges` still
  have their prior behavior. Their bound requires reserve-before-commit semantics
  for synchronous mutations and package-removal reconciliation; dropping a
  committed notification would be incorrect.
- Chooser-only activity/session work and its legacy callbacks/timers.
- Saved opaque `AccountSessions` storage and retained payload bytes. Its existing
  1024-entry policy is unchanged; this round only moves consumption behind
  operation admission.
- Arbitrary Bundle/string/list byte admission, and process-wide resource or
  fairness guarantees across unrelated service owners.
- The other DNS/HTTP/async-owner components of NATIVE-10 and the wider #178
  measurement/hardware acceptance criteria.

The pre-publication overlap audit refreshed all 48 open PR file lists on
22 November at 12:30 UTC. None touched `AccountRequests.java`,
`AccountManagerService.java` or `AccountSessions.java`. Independent review of the
actual local commit and fresh head-specific CI remain required before this
sub-round is treated as ready.
