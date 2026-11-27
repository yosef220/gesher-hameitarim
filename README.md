# מיתר

**מבוסס על Gesher.** אפליקציות אנדרואיד על Windows, עם ממשק בעברית.

עד גרסה 1.1.0 השם היה "גשר המיתרים" (Gesher HaMeitarim).

## הקרדיט: Gesher המקורי

מיתר מבוסס על **Gesher**, שיצר **palmoni5**. הוא פתח את הפרויקט ב-19 באוקטובר 2026, ובחמישה שבועות כתב בעצמו את רובו המכריע: 3,163 מתוך 3,342 הקומיטים עד הגרסה האחרונה שפורסמה כקוד פתוח. תרמו לו גם yom-chadash, ‏Y-PLONI, ‏ztcebuck, ‏ARI212121, ‏dudu, ‏talmidhon, ‏Lev-Good, ‏israelv ו-tsoolgee, ועוד תורמים שה-PRs שלהם נכללו כאן, כמו dudua99. הקרדיט של כל אחד מהם שמור בהיסטוריית הקוד.

**למה יש המשך:** ב-25 בנובמבר 2026 עבר Gesher לרישיון קנייני, ובאותו ערב המאגר שלו נסגר לציבור. הגרסה האחרונה שפורסמה תחת Apache 2.0 נשארת פתוחה לפי הרישיון הזה, וממנה מיתר ממשיך: עם התיקונים שנכנסו ל-Gesher ולא יצאו בגרסה רשמית, ממשק בעברית, עדכונים אוטומטיים, והתקנה מעל Gesher ששומרת את האפליקציות.

**תודה** ל-palmoni5 ולכל מי שתרם ל-Gesher. בלי העבודה שלהם, הפרויקט הזה לא היה קיים.

## Credit: the original Gesher

Meitar is based on **Gesher**, created by **palmoni5**, who started the project on 19 October 2026 and wrote the overwhelming majority of it: 3,163 of the 3,342 commits up to its last open-source release. Contributors include yom-chadash, Y-PLONI, ztcebuck, ARI212121, dudu, talmidhon, Lev-Good, israelv and tsoolgee, and others whose pull requests are included here, such as dudua99. Each contributor's credit is kept in the git history.

On 25 November 2026 Gesher moved to a proprietary license, and its repository was closed to the public that evening. Its last version released under the Apache License 2.0 remains available under that license, and Meitar continues from it.

Thank you to palmoni5 and everyone who contributed to Gesher.

---

*מכאן והלאה: ה-README המקורי של Gesher, שמתאר את הטכנולוגיה. The rest of this page is Gesher's original README.*

<p align="center">
  <img src="assets/gesher.png" alt="Gesher Logo" width="160"/>
</p>

# Gesher

**Run Android apps on Windows as native Windows processes — no emulator, no virtual machine.**

Gesher (Hebrew: *bridge*) is to Android what Wine is to Windows: a compatibility
layer. Double-click an `.apk`, and the app runs in an ordinary window, at native
speed, with no hidden VM and no Android image to boot.

> **Release: v0.1.0** — Native execution of Android applications on Windows with ART JIT, HWUI/Direct3D acceleration, WASAPI audio, Camera/Location subsystems, microG GMS stubs, ARM64-to-x64 binary translation, and seamless desktop integration.
> See the [architecture overview](docs/architecture.md).

## Security: Android app isolation

Gesher's packaged launchers run app processes in Windows AppContainers.
Gesher's Windows brokers provide access to authorized devices and desktop
operations. Android permissions continue to govern Android APIs.
Install only apps you trust. [App isolation and upgrades](docs/sandbox.md)

## How it works

Instead of rewriting Android, Gesher compiles the Android Open Source Project's
own runtime and framework for Windows and replaces only the layers that talk to
the Linux kernel:

```
 .apk ─► APK loader       manifest, resources, dex, native libs
         ART (with JIT)   Android's own Java runtime, ported to Windows
         framework.jar    the real Android framework
           └ system services re-implemented in-process
         HWUI + Skia      → OpenGL ES → ANGLE → Direct3D 11
         native .so       ELF loader + bionic on Win32 (+ arm64 translation)
         integration      windows, input, IME, clipboard, files, notifications
```

Full design: [docs/architecture.md](docs/architecture.md).

The [November 16 performance follow-up](docs/research/runtime-performance-followup-2026-11-16.md)
adds measured audio, path, WebView, camera, framework-build and dashboard-row
improvements, with independent QA and Windows/ART checks.

The [November 16 performance audit](docs/research/runtime-performance-audit-2026-11-16.md)
records subsequent allocation, polling, camera, graphics, logging and desktop
improvements, independent QA, actual Windows/ART checks and remaining limits.

The [earlier runtime performance audit](docs/research/runtime-performance-audit-2026-11-14.md)
maps execution paths and records measured allocation, file-I/O and archive-scan
reductions, frame-cache lifetime repairs, regression coverage and remaining work.

## Compatibility

The [November 16 compatibility follow-up](docs/research/android-runtime-followup-2026-11-16.md)
refreshes the repository/API map and repairs network registration, AAudio
lifetime/channel queries and native/translated thread attributes, with
independent QA and mandatory Windows guest checks.

The [November 16 runtime contract audit](docs/research/android-runtime-contracts-2026-11-16.md)
maps all tracked paths, records SDK/service/JNI review queues, and repairs
socket, DNS, activity, binding, media lifetime and Bluetooth contracts with
independent QA, reproducible evidence and explicit remaining Windows gates.

The [November 14 contract audit](docs/research/android-contract-audit-2026-11-14.md)
maps every tracked path, refreshes the SDK and service/JNI review queues, and
repairs pthread clocks, location completion, NSD values, media callbacks and
Windows mouse-capture cancellation with independent QA and mandatory CI gates.

The [Android/Windows contract audit](docs/research/android-windows-compatibility-2026-11-14.md)
maps every repository file, records SDK36 gap candidates, and repairs ELF lookup,
memory advice, media ownership, audio negotiation, task snapshots and services.
It includes independent regression controls, Windows gates and remaining gaps.

The [lifecycle contract audit](docs/research/android-lifecycle-contracts-2026-11-13.md)
maps the runtime, records a fresh SDK inventory, and repairs network callbacks,
message-port ownership, timers and media lifetimes with independent QA.

Android compatibility is partial. Apps can still fail on missing module APIs,
native imports or backend behavior. The
[earlier compatibility audit](docs/research/android-compatibility-deep-audit-2026-11-13.md)
records concrete crash-contract repairs, regression coverage and substantial
remaining work; a successful build or symbol lookup alone does not prove that
an arbitrary APK will run correctly.

The [compatibility follow-up](docs/research/android-compatibility-followup-2026-11-13.md)
adds a repository map, exhaustive SDK gap lists, and focused service, filesystem
and media repairs with independent regression controls and Windows gates.
The earlier deep audit builds on that work with network and Wi-Fi data contracts,
event-loop fairness, audio-state and native-window repairs, and a fresh combined
SDK inventory that separates structural gaps from demonstrated failures.

## Principles

- **No VM, no emulator.** One Windows process per app.
- **Light.** Nothing runs when no app is open.
- **No store.** Gesher opens `.apk` files the user already has.
- **Respects the host.** Networking and TLS use Windows' own certificate
  store, so content filters and corporate proxies work unchanged.
- **CI does the heavy lifting.** Every build and test runs on GitHub Actions;
  contributors don't need a powerful machine.

## Building

See the [build and package guide](docs/build-and-package.md) for source identity,
complete installer suppliers and local validation.

The production build runs on Linux or WSL and produces Windows x64 binaries.
Requirements: CMake 3.24+, Ninja, Python 3.12+, git, curl, and GNU Make. The
recipe downloads the pinned [llvm-mingw](https://github.com/mstorsjo/llvm-mingw)
archive and builds a separate runtime overlay fixing a pthread cancellation
lock inversion during TLS destructor logging. Its source, ABI and actual link
ownership checks also run in CI; the original publisher cache stays intact.

```sh
tools/fetch-aosp.sh                       # pinned AOSP sources + Gesher patches
python3 tools/toolchain/prepare_pthread_cancel.py build
export GESHER_HOST_PTHREAD_SELECTION=publisher-cancel
export GESHER_PTHREAD_CANCEL_RECEIPT="$PWD/out-pthread-cancel/pthread-cancel-receipt.json"
export GESHER_PTHREAD_CANCEL_RECEIPT_SHA256="$(sha256sum "$GESHER_PTHREAD_CANCEL_RECEIPT" | cut -d' ' -f1)"
gesher_llvm="$PWD/out-pthread-cancel/llvm-mingw-20261006-ucrt-ubuntu-22.04-x86_64"
cmake --fresh -S . -B out -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain-llvm-mingw.cmake \
  -DLLVM_MINGW="$gesher_llvm" \
  -DCMAKE_PROJECT_INCLUDE="$PWD/tools/toolchain/pthread_cancel_link.cmake"
ninja -C out
python3 tools/toolchain/prepare_pthread_cancel.py links --receipt "$GESHER_PTHREAD_CANCEL_RECEIPT"
```

An existing exact compiler archive can be supplied with `build --archive PATH`;
its SHA256 is still checked. See the [runtime repair and evidence notes](docs/research/pthread-self-cancellation-2026-11-22.md)
for the separate publisher reference and selected-minimum experiment.

Outputs include:

- `dalvikvm.exe`: The ported ART runtime with JIT compiler.
- `gesher-exec.exe`: App process host and launcher.
- `installer/gesher-setup-*.exe`: Complete Windows installer and shell integration,
  produced separately by the CI `package` job after supplier verification.

Tests: `tests/build-test-apps.sh out/test-apps` (needs a JDK), then
`tests/windows/run-tests.ps1` on Windows.

## Updates

The Gesher Control Center checks GitHub Releases for stable updates and can
download and install a newer version. Automatic checks can be disabled; installing
requires confirmation and preserves installed Android apps and their data.
See [updating Gesher](docs/updates.md) for behavior, release packaging and tests.

## License / רישיון

Meitar is offered under the [PolyForm Strict License 1.0.0](LICENSE):
noncommercial use only, with no right to distribute it or to make changes or new
works based on it. Any other use, including use in a business, needs a separate
written license from the repository owner. The parts that come from Gesher, up to
its last version released under the Apache License 2.0, remain under
[Apache 2.0](LICENSE-APACHE). See [NOTICE.md](NOTICE.md).

מיתר מופץ לפי [PolyForm Strict License 1.0.0](LICENSE): שימוש למטרות לא
מסחריות בלבד, בלי זכות להפיץ, לשנות או לבנות ממנו גרסאות. לכל שימוש אחר, כולל
בעסק, צריך רישיון נפרד בכתב מבעל המאגר. החלקים שמקורם ב-Gesher נשארים תחת
[Apache 2.0](LICENSE-APACHE). פירוט ב-[NOTICE.md](NOTICE.md).

---

## בעברית

‏**גשר** מריץ אפליקציות אנדרואיד על Windows כתוכנות רגילות, בלי אמולטור ובלי
מכונה וירטואלית. המטרה היא כלי קל שפותח קובצי ‎`.apk` בלחיצה כפולה ומכבד את
הסינון שמותקן במחשב.

גרסה **v0.1.0** כוללת מנוע ART עם JIT, האצת חומרה HWUI/Direct3D, סאונד WASAPI, תמיכת מצלמה ומיקום, שירותי microG GMS, תרגום ספריות ARM64, ושילוב מלא בשולחן העבודה של Windows.

### אבטחה: בידוד אפליקציות Android

המשגרים שמותקנים עם גשר מריצים תהליכי אפליקציות בתוך Windows AppContainer.
שירותי גשר ב־Windows מתווכים גישה מורשית להתקנים ולפעולות בשולחן העבודה.
הרשאות Android ממשיכות לחול על ממשקי Android. יש להתקין אפליקציות מהימנות בלבד.
[בידוד אפליקציות ושדרוגים](docs/sandbox.md)
