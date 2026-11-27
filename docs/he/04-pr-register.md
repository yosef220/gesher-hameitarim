# מרשם ה-PRs — כל מה שלא מוזג ל-upstream

> מסמך שנוצר אוטומטית על ידי `tools/integration/build_pr_register.py`. אל תערכו אותו ידנית — עדכנו את הנתונים והריצו שוב.

**נקודת ייחוס:** `gesher-runtime/gesher` main בקומיט `669d40a12` (25.11.2026). סימולציית המיזוג רצה עם `git merge-tree --write-tree` — בלי לגעת בקוד, רק בדיקה אם המיזוג נקי ואילו קבצים מתנגשים.

## תמונת מצב

| מדד | מספר |
|---|---|
| סך כל ה-PRs שנפתחו ב-upstream | 444 |
| מוזגו ל-main | 279 |
| מתוכם מוזגו אחרי v0.2.0 ועדיין לא שוחררו למשתמשים | 102 |
| פתוחים (ממתינים לאישור) | 97 |
| נסגרו בלי מיזוג | 68 |
| ענפים ייחודיים בפורק Lev-Good | 1 (`fix/app-compat`, 7 קומיטים) |

### חלוקה לגלי אינטגרציה

| גל | מספר PRs | פתוחים | סגורים |
|---|---|---|---|
| גל 0 — כבר בפנים (אין מה למזג) | 10 | 0 | 10 |
| גל 1 — תיקונים לבאגים ולבקשות שדווחו | 18 | 12 | 6 |
| גל 2 — נכנסים ברצף בלי שום התנגשות | 33 | 30 | 3 |
| גל 3 — נקיים מול main אבל מתנגשים זה בזה | 24 | 21 | 3 |
| גל 4 — פתוחים שמתנגשים מול main | 34 | 34 | 0 |
| גל 5 — סגורים שמתנגשים מול main (נבדק כפילות מול PRs מאחדים) | 44 | 0 | 44 |
| ללא תוכן מוצר — פיילוט CI עם היסטוריה נפרדת | 2 | 0 | 2 |

### הקבצים שמתנגשים הכי הרבה (מול main)

| קובץ | מספר PRs שמתנגשים בו |
|---|---|
| `.github/workflows/ci.yml` | 25 |
| `app/java/com/gesher/server/PackageManagerService.java` | 15 |
| `tools/net-tcp-priority/test-selected-policy.py` | 15 |
| `.github/workflows/framework.yml` | 11 |
| `app/java/com/gesher/server/ActivityManagerService.java` | 7 |
| `app/java/com/gesher/server/ActivityTaskManagerService.java` | 7 |
| `app/java/com/gesher/server/Services.java` | 6 |
| `compat/devices/devices.cmake` | 6 |
| `tools/net-tcp-priority/run-component.ps1` | 6 |
| `tools/net-tcp-priority/test-helper-metadata.ps1` | 6 |
| `app/java/com/gesher/server/Installer.java` | 6 |
| `tests/windows/tracks/96-deep-compatibility.ps1` | 6 |

## פורק Lev-Good

- ענף `fix/app-compat` (כולל את התג `v0.2.0-lev1`): **מתנגש מול main**, 2 קבצים מתנגשים: `app/java/com/gesher/server/AccountManagerService.java`, `tools/package/gesher-control-panel.ps1`
- תוכן: תיקון `getPreviousName` ב-AccountManager (חופף חלקית ל-#448 שכבר מוזג), דילוג על authority מתנגש של ספק תוכן (בנק לאומי), כינוי לשירות START_1P של Play Games, פרוקסי SOCKS5 (גם PR #493), נתיבי profman לשם משתמש בעברית (גם PR #454, issue #355), mkfifo עבור Realm, מחוון הפעלה ולוגים במתקין, ועיצוב מחדש של מרכז הבקרה (פריסה דו-טורית + חיפוש חי).

## גל 0 — כבר בפנים (אין מה למזג)

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #392 | נסגר | בדיקות | שירותי מערכת | — | התוכן כבר ב-main | — | test(appops): probe retirement monitors without reversing lock order | yom-chadash |
| #365 | נסגר | שינוי | תשתית CI ובדיקות | — | התוכן כבר ב-main | — | Configure GitHub Sponsors for Gesher | palmoni5 |
| #211 | נסגר | תיקון | שירותי מערכת | — | התוכן כבר ב-main | — | fix(statusbar): a statusbar service without a SystemUI bar | palmoni5 |
| #207 | נסגר | תיקון | שירותי מערכת | — | התוכן כבר ב-main | — | fix(thermal): register thermal status listeners, as Android does without a HAL | palmoni5 |
| #204 | נסגר | תיקון | שכבת POSIX | — | התוכן כבר ב-main | — | fix(mman): never fail an ordinary mapping because of its hint | palmoni5 |
| #194 | נסגר | שינוי | ספריית C (bionic) | — | התוכן כבר ב-main | — | bionic: bound SelectImpl fd_set clearing to nfds | ztcebuck |
| #189 | נסגר | בדיקות | שכבת POSIX | — | התוכן כבר ב-main | — | test(posix): reach the real deadline in timeout cleanup controls | palmoni5 |
| #162 | נסגר | שינוי | כללי | — | התוכן כבר ב-main | — | Audit pinned SDK36/37 API history and extension metadata (A07) | palmoni5 |
| #127 | נסגר | יכולת חדשה | Wi-Fi | — | התוכן כבר ב-main | — | feat(wifi): implement SDK36 configuration value contracts (A02) | palmoni5 |
| #15 | נסגר | שינוי | כללי | — | — | — | Let the device idle after apps close; live-refresh the control panel | palmoni5 |

## גל 1 — תיקונים לבאגים ולבקשות שדווחו

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #493 | פתוח | יכולת חדשה | רשת | #364 | נכנס נקי מול main | — | feat(net): support SOCKS5 proxy via Windows proxy settings and GESHER_PROXY | Lev-Good |
| #491 | פתוח | תיקון | ממשק ומרכז הבקרה | #472 | נכנס נקי מול main | — | fix(control-panel): show informational App Info dialog instead of uninstall prompt | palmoni5 |
| #484 | נסגר | תיקון | ספריית C (bionic) | #301, #480 | נכנס נקי מול main | — | fix(bionic): export Android's libstdc++.so (operator new/delete, guards) | palmoni5 |
| #475 | פתוח | יכולת חדשה | אימות ואבטחה | #339 | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/AuthService.java`<br>`app/java/com/gesher/server/AuthServiceHost.java`<br>`app/java/com/gesher/server/PackageManagerService.java`<br>ועוד 13 | feat(auth): integrate Windows Hello credentials and Android Keystore | dudua99 |
| #471 | נסגר | יכולת חדשה | אימות ואבטחה | #339 | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/AuthService.java`<br>`app/java/com/gesher/server/Services.java`<br>`compat/devices/devices.cmake`<br>ועוד 7 | feat(keystore): enforce user authentication through a Windows Hello-bound key (ADR 0092; stacked on #366) | dudua99 |
| #470 | פתוח | יכולת חדשה | אימות ואבטחה | #339 | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/AuthService.java`<br>`app/java/com/gesher/server/PackageManagerService.java`<br>`app/java/com/gesher/server/Services.java`<br>ועוד 11 | feat(auth): device-credential confirmation reaches apps through Windows Hello (ADR 0091, phase 2b; stacked on #366) | dudua99 |
| #464 | פתוח | תיקון | חשבונות ושירותי Google | #335 | נכנס נקי מול main | — | fix(gms): report no Play services, Google account or push token that does not exist (#335) | dudua99 |
| #455 | נסגר | תיקון | חשבונות ושירותי Google | #304, #316 | מתנגש מול main | `app/java/com/gesher/server/AccountManagerService.java` | fix(server): app compatibility fixes for AccountManager, ContentProviders, and Play Games START_1P | Lev-Good |
| #454 | נסגר | תיקון | ניהול חבילות והתקנה | #355 | נכנס נקי מול main | — | fix(dexopt): normalize profman paths via Device.dataDir() 8.3 prefix (#355) | Lev-Good |
| #432 | פתוח | שינוי | כללי | #301 | נכנס נקי מול main | — | Run apps protected by NetEase Yidun (Dreamehome) | palmoni5 |
| #427 | פתוח | שינוי | בידוד ואבטחה | #314 | מתנגש מול main | `app/java/com/gesher/server/AppDataStorage.java`<br>`app/java/com/gesher/server/CameraDeviceUser.java`<br>`compat/devices/camera_mf.cc`<br>`compat/devices/devices.cmake`<br>ועוד 2 | Run packaged Android guests in Windows AppContainers | palmoni5 |
| #421 | פתוח | שינוי | Wi-Fi | #463 | נכנס נקי מול main | — | Declare hardware system features from real hardware: sensors, Wi-Fi, telephony, GLES 3.0 and the rest | palmoni5 |
| #414 | פתוח | שינוי | USB | #407 | נכנס נקי מול main | — | USB storage and CardWake compatibility | palmoni5 |
| #403 | נסגר (טיוטה) | שינוי | Wi-Fi | #375 | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java` | Wi-Fi part 2: network specifier requests and suggestions through user-approved Windows profiles | palmoni5 |
| #402 | נסגר | שינוי | Wi-Fi | #375 | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java` | Wi-Fi part 1: complete SDK 36 WifiManager and declare android.hardware.wifi from real WLAN hardware | palmoni5 |
| #340 | פתוח | יכולת חדשה | אימות ואבטחה | #339 | מתנגש מול main | `app/java/com/gesher/server/Services.java`<br>`docs/research/windows-hello-native-spec.md`<br>`tests/biometrics/AuthServiceContracts.java.in`<br>`tools/test_auth_service_contracts.py` | feat(auth): register IAuthService with AOSP's sensor-less answers (ADR 0091, phase 1) | dudua99 |
| #332 | פתוח | שינוי | ממשק ומרכז הבקרה | #310, #312, #322, #431 | נכנס נקי מול main | — | Let the user grant special app access from the Control Center | palmoni5 |
| #328 | פתוח | תיקון | ניהול חבילות והתקנה | #355 | נכנס נקי מול main | — | fix(dexopt): pass dex2oat and profman their arguments as UTF-8 | palmoni5 |

## גל 2 — נכנסים ברצף בלי שום התנגשות

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #487 | פתוח | יכולת חדשה | ממשק ומרכז הבקרה | — | נכנס נקי מול main | — | feat(camera): Control Center setting to choose a PC image instead of a camera capture | palmoni5 |
| #479 | פתוח | תיקון | חלונות | — | נכנס נקי מול main | — | fix(window): keep an app window within its display (decision needed) | palmoni5 |
| #466 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(intents): mailto, tel, sms and geo intents reach the Windows handler that is registered for them | dudua99 |
| #451 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(tts): Android Text-to-speech over Windows voices | dudua99 |
| #441 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): bypass multibyte staging for ASCII wide conversion | yom-chadash |
| #436 | פתוח | בדיקות | תשתית CI ובדיקות | — | נכנס נקי מול main | — | test(services): enforce fixture persistence and provider readmission | yom-chadash |
| #434 | פתוח | ביצועים | ניהול חבילות והתקנה | — | נכנס נקי מול main | — | perf(uri-grants): retire installed grants once per package publication | yom-chadash |
| #428 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): skip zero-free Annex-B words in complete MP4 writes | yom-chadash |
| #424 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): reuse the successful tree-deletion route | yom-chadash |
| #420 | פתוח | תשתית CI | אימות ואבטחה | — | נכנס נקי מול main | — | ci: reuse bounded authenticated reads for public release versions | yom-chadash |
| #416 | פתוח | יכולת חדשה | אחסון וספקי תוכן | — | נכנס נקי מול main | — | feat(downloads): serve content://downloads and run DownloadManager requests in the system server | dudua99 |
| #415 | פתוח | ביצועים | מיקום | — | נכנס נקי מול main | — | perf(java): avoid Formatter allocations in service identity digests | yom-chadash |
| #412 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): reuse exact row conversion for odd I420 crops | yom-chadash |
| #411 | נסגר (טיוטה) | בדיקות | כללי | — | נכנס נקי מול main | — | Test UsbManager during installed app startup | palmoni5 |
| #408 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): remove registry locking from pthread key assignment | yom-chadash |
| #404 | פתוח | שינוי | מדיה | — | נכנס נקי מול main | — | media: reuse exact half-phase resampler coefficients within each mix | yom-chadash |
| #394 | פתוח | בדיקות | רשת | — | נכנס נקי מול main | — | test(dns): wait for real timeout callback and executor retirement | yom-chadash |
| #393 | פתוח | תיקון | תשתית CI ובדיקות | — | נכנס נקי מול main | — | fix(ci): isolate TSF output metadata observers from pending writers | yom-chadash |
| #390 | פתוח | תיקון | שמע | — | נכנס נקי מול main | — | fix(audio): preserve prepared blocking input during catch-up mixing | yom-chadash |
| #389 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(camera): reuse exact chroma terms for matching NV12 RGBA frames | yom-chadash |
| #384 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): remove the registry mutex from pthread key reads | yom-chadash |
| #380 | פתוח | שינוי | שמע | — | נכנס נקי מול main | — | Implement Android volume effects for OpenSL ES players | palmoni5 |
| #374 | נסגר | תשתית CI | תשתית CI ובדיקות | — | נכנס נקי מול main | — | ci(automerge): release with merge commits instead of squash | palmoni5 |
| #353 | פתוח | ביצועים | ניהול חבילות והתקנה | — | נכנס נקי מול main | — | perf(pm): generate component families once per intent query | yom-chadash |
| #348 | פתוח | ביצועים | תרגום arm64 | — | נכנס נקי מול main | — | perf(arm64): trim unused active TLS pages after initialization | yom-chadash |
| #345 | פתוח | ביצועים | ניהול חבילות והתקנה | — | נכנס נקי מול main | — | perf(packages): reuse visibility metadata by package generation | yom-chadash |
| #341 | פתוח | יכולת חדשה | רשת | — | נכנס נקי מול main | — | feat(http): stream Brotli responses with bounded native ownership | yom-chadash |
| #338 | פתוח | ביצועים | כללי | — | נכנס נקי מול main | — | perf(content): index observer dispatch while preserving Android delivery | yom-chadash |
| #336 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): reuse released AVC input and bitstream buffers | yom-chadash |
| #290 | פתוח | ממשק | ממשק ומרכז הבקרה | — | נכנס נקי מול main | — | ui: restore MessageBox icons and sounds in host prompts | palmoni5 |
| #266 | פתוח | ביצועים | אימות ואבטחה | — | נכנס נקי מול main | — | perf(accounts): bound authenticator request lifetimes (NATIVE-10 A) | palmoni5 |
| #149 | פתוח | שינוי | גילוי שירותים ברשת (NSD) | — | נכנס נקי מול main | — | Implement binary-preserving NSD resolution and cancellation (N46) | palmoni5 |
| #81 | נסגר | שינוי | מדיה | — | נכנס נקי מול main | — | M07: Implement SMTC synchronization in MediaSessionService | palmoni5 |

## גל 3 — נקיים מול main אבל מתנגשים זה בזה

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #492 | פתוח | ביצועים | ממשק ומרכז הבקרה | — | נכנס נקי מול main | — | perf(control-panel): eliminate redundant startup compilation and double refresh | palmoni5 |
| #490 | פתוח | יכולת חדשה | זהות המכשיר | — | נכנס נקי מול main | — | feat(identity): report the PC's real manufacturer and model instead of a Pixel 8 | palmoni5 |
| #489 | פתוח | תיקון | אימות ואבטחה | — | נכנס נקי מול main | — | fix(logging): redact credentials before logs are persisted | palmoni5 |
| #478 | פתוח | יכולת חדשה | תרגום arm64 | — | נכנס נקי מול main | — | feat(arm64): real fork and clone for arm64 guest code | palmoni5 |
| #473 | פתוח | יכולת חדשה | אימות ואבטחה | — | נכנס נקי מול main | — | feat(credentials): passkeys through Windows' WebAuthn API (Credential Manager, ADR 0093) | dudua99 |
| #469 | פתוח | תיקון | רשת | — | נכנס נקי מול main | — | fix(net): metered state and background-data restriction from Windows | dudua99 |
| #468 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(accessibility): CaptioningManager follows Windows' caption settings | dudua99 |
| #467 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(location): CountryDetector from Windows' home region | dudua99 |
| #465 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(speech): Android speech recognition over Windows speech recognition | dudua99 |
| #452 | פתוח | יכולת חדשה | חלונות | — | נכנס נקי מול main | — | feat(print): Android printing to Windows printers | dudua99 |
| #450 | פתוח | יכולת חדשה | מדיה | — | נכנס נקי מול main | — | feat(media): serve content://media from a MediaStore index over the shared volume | dudua99 |
| #430 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): bound stable scandir sorting after 8N swaps | yom-chadash |
| #413 | פתוח | ביצועים | ספריית C (bionic) | — | נכנס נקי מול main | — | perf(bionic): scan bounded words in reverse byte search | yom-chadash |
| #401 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): walk exact ImageReader plane coordinates without per-pixel division | yom-chadash |
| #372 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): avoid repeated frame walks for equal-rate capture | yom-chadash |
| #360 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): avoid same-size RGBA coordinate remapping | yom-chadash |
| #354 | פתוח | ביצועים | רשת | — | נכנס נקי מול main | — | perf(http2): resolve fixed provider bindings once per framework loader | yom-chadash |
| #350 | פתוח | שינוי | רשת | — | נכנס נקי מול main | — | net: bound unary HTTP bursts and preserve cancellation progress | yom-chadash |
| #349 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): transfer exact packed HEVC output without a frame copy | yom-chadash |
| #347 | פתוח | שינוי | מדיה | — | נכנס נקי מול main | — | media: halve MP3, Vorbis and Opus decode allocations with owned scratch | yom-chadash |
| #342 | פתוח | ביצועים | מדיה | — | נכנס נקי מול main | — | perf(media): transfer owned packed AVC frames without copying | yom-chadash |
| #84 | נסגר | שינוי | אינטנטים וקיצורי דרך | — | נכנס נקי מול main | — | F38: Dynamic Shortcuts support | palmoni5 |
| #83 | נסגר | שינוי | אינטנטים וקיצורי דרך | — | נכנס נקי מול main | — | F18: Ordered Broadcasts support | palmoni5 |
| #82 | נסגר | שינוי | חלונות | — | נכנס נקי מול main | — | W08: Multi-window/Freeform support | palmoni5 |

## גל 4 — פתוחים שמתנגשים מול main

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #461 | פתוח | יכולת חדשה | שכבת POSIX | — | מתנגש מול main | `CONTRIBUTING.md`<br>`compat/arm64/dll/translator.cc`<br>`tests/native/arm64_pending_rollback_host.cc.in`<br>`tools/net-tcp-priority/qualified/ofd-stream-source.json`<br>ועוד 1 | feat(posix): real cross-process ptrace with Yama permissions and wait4 stops | palmoni5 |
| #440 | פתוח | בדיקות | אחסון וספקי תוכן | — | מתנגש מול main | `app/java/com/gesher/server/CameraDeviceUser.java`<br>`compat/devices/camera_mf.cc`<br>`compat/devices/devices.cmake`<br>`compat/hwui/window/gesher_window.cc`<br>ועוד 1 | test: restore the SQLite path fixture on #427 | yom-chadash |
| #437 | פתוח | בדיקות | תרגום arm64 | — | מתנגש מול main | `app/java/com/gesher/server/ApkPackage.java`<br>`app/java/com/gesher/server/ContentProviders.java`<br>`compat/arm64/dll/guest_libc.cc`<br>`compat/arm64/dll/translator.cc`<br>ועוד 4 | test: restore the ARM64 pending rollback fixture for #432 | yom-chadash |
| #435 | פתוח | תשתית CI | תשתית CI ובדיקות | — | מתנגש מול main | `tools/ci/github_read.py`<br>`tools/net-tcp-priority/run-component.ps1`<br>`tools/net-tcp-priority/test-helper-metadata.ps1` | ci: bound recovery for unframed GitHub EOF reads | yom-chadash |
| #429 | פתוח | שינוי | רשת | — | מתנגש מול main | `app/java/com/gesher/server/AppDataStorage.java`<br>`app/java/com/gesher/server/CameraDeviceUser.java`<br>`compat/devices/camera_mf.cc`<br>`compat/devices/devices.cmake`<br>ועוד 2 | Add permission-scoped NETLINK_ROUTE on Windows | palmoni5 |
| #410 | פתוח | בדיקות | רשת | — | מתנגש מול main | `tests/native/dns_admission_host.cc.in` | test(dns): reserve loopback UDP and TCP peer ports together | yom-chadash |
| #405 | פתוח | בדיקות | חלונות | — | מתנגש מול main | `.github/workflows/services-geocoder-worker-component.yml` | test(windows): observe PID census across retained-root exit | yom-chadash |
| #391 | פתוח | שינוי | אחסון וספקי תוכן | — | מתנגש מול main | `app/java/com/gesher/server/DesktopUsageStatsService.java`<br>`compat/media/audio/capture.cc`<br>`compat/media/player/player.cc`<br>`docs/graphics.md`<br>ועוד 11 | Round 2: cumulative integration, retained damage, usage and real storage | palmoni5 |
| #382 | פתוח | ביצועים | מדיה | — | מתנגש מול main | `compat/devices/camera_frames.cc` | perf(media): copy matching ImageReader RGBA frames in bulk | yom-chadash |
| #379 | פתוח | בדיקות | חשבונות ושירותי Google | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/Installer.java`<br>`app/java/com/gesher/server/PackageManagerService.java`<br>`tests/dex-services/gesher/services/PackageServiceQueriesTest.java` | test(accounts): remove owned identity files in #122 fixture cleanup | yom-chadash |
| #373 | פתוח | ביצועים | ניהול חבילות והתקנה | — | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java`<br>`tests/search/SearchableHost.java` | perf(package): reuse exact UID owner metadata and batch cold queries | yom-chadash |
| #370 | פתוח | ביצועים | ספריית C (bionic) | — | מתנגש מול main | `tools/net-tcp-priority/test-selected-policy.py` | perf(bionic): retain only caller-visible snprintf output | yom-chadash |
| #363 | פתוח | בדיקות | לוח העתקה | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/Dexopt.java` | test(clipboard): verify the real clipboard challenge before the background probe | yom-chadash |
| #362 | פתוח | תיקון | ממשק ומרכז הבקרה | — | מתנגש מול main | `tests/i18n/UiMessagesTest.java` | Fix bidi rendering in package consent dialogs | palmoni5 |
| #361 | פתוח | ביצועים | Binder | — | מתנגש מול main | `tests/native/dns_admission_host.cc.in`<br>`tools/net-tcp-priority/test-selected-policy.py` | perf(binder): serialize transactions directly into the connection reply | yom-chadash |
| #359 | פתוח | בדיקות | שירותי מערכת | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`tests/dex-services/gesher/services/ExactAlarmContractTest.java`<br>`tests/dex-services/gesher/services/PendingIntentContractTest.java` | test(alarms): restore AMS lifecycle observer owner in #158 fixture | yom-chadash |
| #358 | פתוח | בדיקות | חיישנים | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/ActiveServices.java`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`app/java/com/gesher/server/ActivityTaskManagerService.java`<br>ועוד 3 | test(alarms): initialize sensor owner in exact-alarm fixture for #245 | yom-chadash |
| #352 | פתוח | ביצועים | ספריית C (bionic) | — | מתנגש מול main | `tools/net-tcp-priority/test-selected-policy.py` | perf(stdio): reuse pinned stream owners during formatted input | yom-chadash |
| #343 | פתוח | ביצועים | ספריית C (bionic) | — | מתנגש מול main | `tools/net-tcp-priority/test-selected-policy.py` | perf(bionic): wake child waiters on lifecycle notifications | yom-chadash |
| #337 | פתוח | ביצועים | ספריית C (bionic) | — | מתנגש מול main | `tools/net-tcp-priority/test-selected-policy.py` | perf(bionic): scan buffered line spans under one stream owner | yom-chadash |
| #296 | פתוח | תיקון | שכבת POSIX | — | מתנגש מול main | `compat/posix/src/native_fence_internal.h`<br>`tools/net-tcp-priority/run-component.ps1`<br>`tools/net-tcp-priority/test-helper-metadata.ps1`<br>`tools/net-tcp-priority/test-selected-policy.py` | fix(posix): honor receiver-selected flags for native-fence SCM_RIGHTS | palmoni5 |
| #271 | פתוח | שינוי | רשת | — | מתנגש מול main | `docs/network.md` | net: retire connectivity observation when no owner needs it | palmoni5 |
| #269 | פתוח | ביצועים | רשת | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`cmake/aosp/conscrypt.cmake`<br>`compat/net/trust_store.cc`<br>`compat/net/trust_store.h`<br>ועוד 1 | perf(trust): verified certificate encoding reuse experiment (NATIVE-11) | palmoni5 |
| #268 | פתוח | תיקון | שמע | — | מתנגש מול main | `compat/posix/src/fd.cc`<br>`compat/posix/src/netdb.cc`<br>`compat/posix/src/system.cc` | Fix voice call WASAPI multi-group mixing and add NETLINK_ROUTE socket support | ztcebuck |
| #260 | פתוח | שינוי | שירותי מערכת | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`.github/workflows/framework.yml`<br>`tests/windows/tracks/94-framework-fixes.ps1` | services: enforce foreground promotion manifest permissions (F06) | palmoni5 |
| #256 | פתוח | יכולת חדשה | שכבת POSIX | — | מתנגש מול main | `CMakeLists.txt`<br>`compat/posix/src/fd.cc`<br>`compat/posix/src/stat.cc`<br>`compat/posix/src/system.cc`<br>ועוד 2 | feat(posix): implement mkfifo and POSIX FIFO descriptors | ztcebuck |
| #245 | פתוח | שינוי | אימות ואבטחה | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/ActiveServices.java`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`app/java/com/gesher/server/ActivityTaskManagerService.java`<br>ועוד 3 | sensors: connect NDK queues to the authenticated Windows sensor hub (H01) | palmoni5 |
| #232 | פתוח | ביצועים | שמע | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`compat/media/audio/engine.cc`<br>`compat/media/audio/sink.h`<br>`tools/net-tcp-priority/run-component.ps1`<br>ועוד 1 | perf(audio): suspend output rendering and feeder work while idle | palmoni5 |
| #226 | פתוח | בדיקות | לוח העתקה | — | מתנגש מול main | `.github/workflows/ci.yml` | test: prebuild the owned clipboard foreground actor | palmoni5 |
| #164 | פתוח | שינוי | גילוי שירותים ברשת (NSD) | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`tests/dex-services/gesher/services/PendingIntentContractTest.java`<br>`tools/test_nsd_peer_scope.py` | Implement continuing Windows NSD service-info subscriptions (N46) | palmoni5 |
| #158 | פתוח | שינוי | גילוי שירותים ברשת (NSD) | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`tests/dex-services/gesher/services/PendingIntentContractTest.java` | Implement owned Windows NSD registration and unregistration (N46) | palmoni5 |
| #122 | פתוח | שינוי | אימות ואבטחה | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/Installer.java`<br>`app/java/com/gesher/server/PackageManagerService.java` | Implement authenticated SQLite UserDictionary provider (F15) | palmoni5 |
| #107 | פתוח | תיקון | ספריות נייטיב | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`app/java/com/gesher/server/Installer.java`<br>`cmake/aosp/framework.cmake`<br>`compat/bionic/shim.cc`<br>ועוד 6 | fix(native): enforce classloader namespaces and library identity (N02/N03) | palmoni5 |
| #103 | פתוח | תיקון | ספריות נייטיב | — | מתנגש מול main | `compat/bionic/shim.cc`<br>`compat/elf/elf_loader.cc`<br>`tests/native/elf_lookup_host_test.cc.in`<br>`tools/net-tcp-priority/test-selected-policy.py` | fix(elf): honor symbol versions and dlvsym across guest ABIs (N05) | palmoni5 |

## גל 5 — סגורים שמתנגשים מול main (נבדק כפילות מול PRs מאחדים)

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #400 | נסגר | שינוי | טלפוניה | — | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java`<br>`app/java/com/gesher/server/Services.java` | Telephony over a Windows cellular modem (read-only, data-only) | palmoni5 |
| #397 | נסגר | שינוי | חיישנים | — | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java`<br>`docs/devices.md` | Report FEATURE_SENSOR_* for the sensors SensorManager lists | palmoni5 |
| #396 | נסגר | שינוי | חלונות | — | מתנגש מול main | `app/java/com/gesher/server/PackageManagerService.java`<br>`compat/bionic/egl_gles.cc`<br>`docs/devices.md`<br>`tests/java-performance/CameraSelectionOrientationHost.java.in` | Report the system features Windows backs; declare OpenGL ES 3.0 | palmoni5 |
| #388 | נסגר | תיקון | אינטגרציה מצטברת | — | מתנגש מול main | `compat/media/audio/capture.cc`<br>`compat/media/player/player.cc`<br>`docs/handoff/round1_validation.md`<br>`tests/media/capture_failure_native.cc.in`<br>ועוד 5 | fix: complete round 1 compatibility and performance work from #381 | palmoni5 |
| #378 | נסגר | בדיקות | שירותי מערכת | — | מתנגש מול main | `tests/dex-services/gesher/services/ExactAlarmContractTest.java`<br>`tools/net-tcp-priority/qualified/ofd-stream-source.json`<br>`tools/net-tcp-priority/test-selected-policy.py` | test(alarms): retire owned policy writes before #325 fixture cleanup | yom-chadash |
| #346 | נסגר | תשתית CI | תשתית CI ובדיקות | — | מתנגש מול main | `.github/workflows/ci.yml` | ci: pin framework.yml to a commit on main | palmoni5 |
| #292 | נסגר | תשתית CI | תשתית CI ובדיקות | — | מתנגש מול main | `.github/workflows/ci.yml` | ci: repin the framework recipe to a commit reachable from main | palmoni5 |
| #234 | נסגר | שינוי | שכבת POSIX | — | מתנגש מול main | `.github/workflows/ci.yml` | posix: account reaped direct-child CPU across native and Java (N38) | palmoni5 |
| #225 | נסגר | בדיקות | לוח העתקה | — | מתנגש מול main | `tests/windows/clipboard/ForeignForeground.ps1`<br>`tests/windows/tracks/51-windows3.ps1` | tests: keep clipboard foreground helper on harness PowerShell | palmoni5 |
| #223 | נסגר (טיוטה) | שינוי | אימות ואבטחה | — | מתנגש מול main | `app/java/com/gesher/server/ActivityTaskManagerService.java`<br>`tests/bluetooth/BluetoothRequestHost.java`<br>`tests/dex-services/com/gesher/server/BluetoothRequestFixture.java` | [Validation only] Correct authenticated system identity in #198 Bluetooth CI fixture | palmoni5 |
| #222 | נסגר (טיוטה) | שינוי | בלוטות' | — | מתנגש מול main | `app/java/com/gesher/server/ActivityTaskManagerService.java`<br>`tests/bluetooth/BluetoothRequestHost.java`<br>`tests/dex-services/com/gesher/server/BluetoothRequestFixture.java` | Repair and verify Bluetooth request intents from #198 | palmoni5 |
| #210 | נסגר | יכולת חדשה | שכבת POSIX | — | מתנגש מול main | `compat/posix/posix.cmake`<br>`compat/posix/src/binder.cc`<br>`compat/posix/src/fd.cc`<br>`compat/posix/src/internal.h`<br>ועוד 6 | feat(memfd): store and enforce memfd seals; ASharedMemory as libcutils' memfd regions | palmoni5 |
| #209 | נסגר | יכולת חדשה | רשת | — | מתנגש מול main | `.github/workflows/native-libs.yml`<br>`compat/posix/src/socket.cc`<br>`compat/posix/src/socket_internal.h`<br>`compat/posix/src/system.cc`<br>ועוד 2 | feat(socket): AF_UNIX socketpair credentials (ADR 0088, phase 1) | palmoni5 |
| #208 | נסגר (טיוטה) | תיעוד | אימות ואבטחה | — | מתנגש מול main | `docs/decisions/0088-unix-socket-credentials-and-descriptors.md` | docs(adr): AF_UNIX credentials and descriptor passing (0088, proposed) | palmoni5 |
| #206 | נסגר | תיקון | ספריית C (bionic) | — | מתנגש מול main | `tests/native/libc_test.c` | fix(bionic): export fnmatch to loaded libraries, with bionic's flag values | palmoni5 |
| #205 | נסגר | תיקון | רשת | — | מתנגש מול main | `tests/native/java/gesher/JniTest.java` | fix(jni): know a JNIEnv proxy by its identity, not by its table | palmoni5 |
| #203 | נסגר | תיקון | שכבת POSIX | — | מתנגש מול main | `tests/windows/tracks/96-deep-compatibility.ps1` | fix(posix): report sysname "Linux" from uname, as Android does | palmoni5 |
| #202 | נסגר | תשתית CI | מדיה | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`tests/windows/run-tests.ps1`<br>`tests/windows/test-shards.json`<br>`tools/ci/test_cache_policy.py` | ci: overlap builds with preflight, split the media shard and save caches only from main | palmoni5 |
| #201 | נסגר | תיקון | כללי | — | מתנגש מול main | `app/java/com/gesher/server/ApkPackage.java`<br>`app/java/com/gesher/server/ContentProviders.java`<br>`tests/dex-services/gesher/services/ProviderInitOrderTest.java` | fix(providers): bind and validate each provider component once | palmoni5 |
| #200 | נסגר | תיקון | ניהול חבילות והתקנה | — | מתנגש מול main | `tests/windows/tracks/96-deep-compatibility.ps1` | fix(permission): ship android.safetycenter so the Play Store survives package installs | palmoni5 |
| #195 | נסגר | תשתית CI | תשתית CI ובדיקות | — | מתנגש מול main | `.github/workflows/arm64-windows-self-hosted.yml`<br>`.github/workflows/ci.yml`<br>`.github/workflows/native3-locks-blocking.yml`<br>`.github/workflows/publish-release.yml`<br>ועוד 10 | ci: cut GITHUB_TOKEN REST calls and wait for quota resets instead of failing | palmoni5 |
| #192 | נסגר | תשתית CI | תשתית CI ובדיקות | — | מתנגש מול main | `.github/scripts/app-qa-status.js`<br>`.github/scripts/automerge.md`<br>`.github/scripts/label-automerge.js`<br>`.github/scripts/label-automerge.test.js`<br>ועוד 1 | ci: recover stuck automerge gates; make the legacy QA gate optional once the App gate is required | palmoni5 |
| #163 | נסגר | שינוי | Wi-Fi | — | מתנגש מול main | `tests/dex-services/gesher/services/WifiChannelBlockingValuesContractTest.java`<br>`tools/net-tcp-priority/run-component.ps1`<br>`tools/net-tcp-priority/test-helper-metadata.ps1` | Implement Wi-Fi channel and blocking option value contracts (A02) | palmoni5 |
| #159 | נסגר | שינוי | Wi-Fi | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/build.sh`<br>`tests/dex-services/gesher/services/WifiP2pDiscoveryValuesContractTest.java`<br>`tests/dex-services/gesher/services/WifiP2pNsdValuesContractTest.java`<br>ועוד 1 | Implement Wi-Fi Direct discovery and USD value contracts (A02) | palmoni5 |
| #150 | נסגר | שינוי | Wi-Fi | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/build.sh`<br>`tests/windows/tracks/96-deep-compatibility.ps1` | Implement SDK36 Wi-Fi Direct value contracts (A02) | palmoni5 |
| #148 | נסגר | שינוי | Wi-Fi | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`.github/workflows/framework.yml`<br>`docs/self-hosted-ci.md`<br>`tests/windows/tracks/96-deep-compatibility.ps1` | Implement WifiNetworkSuggestion and Passpoint value contracts (A02) | palmoni5 |
| #146 | נסגר | שינוי | תשתית CI ובדיקות | — | מתנגש מול main | `.github/workflows/ci.yml`<br>`compat/media/audio/capture.cc`<br>`compat/media/audio/capture.h`<br>`compat/media/audio/capture_wasapi.cc`<br>ועוד 14 | Propagate capture availability and disconnect errors across Android APIs | palmoni5 |
| #145 | נסגר | שינוי | חלונות | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/java/com/gesher/server/NotificationIcons.java`<br>`app/java/com/gesher/server/NotificationManagerService.java`<br>`app/java/com/gesher/server/NotificationStore.java`<br>ועוד 10 | Preserve notification ownership when migrating Windows toast identities | palmoni5 |
| #142 | נסגר | שינוי | התראות | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/java/com/gesher/server/NotificationIcons.java`<br>`app/java/com/gesher/server/NotificationStore.java`<br>`tests/dex-services/com/gesher/server/NotificationIdentityDevice.java`<br>ועוד 6 | Separate colliding notification records and images safely | palmoni5 |
| #141 | נסגר | שינוי | Wi-Fi | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`tests/windows/helpers/AssertWifiNetworkSpecifierParcel.ps1`<br>`tests/windows/tracks/96-deep-compatibility.ps1` | Implement WifiNetworkSpecifier value and matching contracts (A02) | palmoni5 |
| #136 | נסגר | שינוי | מיקום | — | מתנגש מול main | `.github/workflows/framework.yml` | Release completed WebView geolocation timeouts | palmoni5 |
| #131 | נסגר | תיקון | ספריית C (bionic) | — | מתנגש מול main | `.github/workflows/binary128-parsing.yml`<br>`.github/workflows/ci.yml`<br>`aosp.lock`<br>`compat/arm64/dll/guest_libc.cc`<br>ועוד 10 | fix(bionic): implement binary128 parsing and ARM64 numeric returns (N39) | palmoni5 |
| #128 | נסגר | בדיקות | תרגום arm64 | — | מתנגש מול main | `.github/workflows/binary128-parsing.yml`<br>`.github/workflows/ci.yml`<br>`.github/workflows/native-callback-cleanup.yml`<br>`aosp.lock`<br>ועוד 12 | test(arm64): qualify native callback cleanup and preserve failure baseline (N15) | palmoni5 |
| #125 | נסגר | תשתית CI | זהות המכשיר | — | מתנגש מול main | `tools/net-tcp-priority/run-component.ps1`<br>`tools/net-tcp-priority/test-helper-metadata.ps1` | ci: refresh reviewed source identity helper pins | palmoni5 |
| #123 | נסגר | תיקון | תרגום arm64 | — | מתנגש מול main | `compat/arm64/dll/arm64_unwind_test.cc`<br>`tools/arm64/build-unwind.py` | fix(arm64): add Windows unwind metadata for native ABI thunks (N15/N18) | palmoni5 |
| #116 | נסגר | שינוי | שכבת POSIX | — | מתנגש מול main | `compat/arm64/dll/guest_libc.cc`<br>`compat/bionic/extra_sys_bionic.cc`<br>`compat/bionic/syscall_bionic.cc`<br>`compat/posix/src/xattr.cc` | Implement persistent Android user extended attributes (N42) | yom-chadash |
| #106 | נסגר | שינוי | Binder | — | מתנגש מול main | `app/java/com/gesher/app/Launcher.java`<br>`app/java/com/gesher/server/ActivityManagerService.java`<br>`app/java/com/gesher/server/PackageManagerService.java`<br>`app/java/com/gesher/server/SettingsProvider.java`<br>ועוד 8 | Support installed Android spell checkers and their Binder sessions (F38) | yom-chadash |
| #104 | נסגר | שינוי | מדיה | — | מתנגש מול main | `cmake/aosp/media.cmake`<br>`compat/devices/camera_frames.cc`<br>`compat/media/jni/media_codec_jni.cc`<br>`compat/media/surface/queue_surface.cc`<br>ועוד 10 | media: implement live AVC bitrate control and MediaCodec metrics (M05) | yom-chadash |
| #94 | נסגר | שינוי | מדיה | — | מתנגש מול main | `cmake/aosp/media.cmake`<br>`compat/devices/camera_frames.cc`<br>`compat/media/jni/media_codec_jni.cc`<br>`compat/media/surface/queue_surface.cc`<br>ועוד 10 | media: preserve MediaCodec output surface timestamps (M18) | yom-chadash |
| #71 | נסגר | יכולת חדשה | אחסון וספקי תוכן | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/java/com/gesher/app/Main.java`<br>`app/java/com/gesher/server/ActivityTaskManagerService.java`<br>`app/java/com/gesher/server/ApkPackage.java`<br>ועוד 22 | feat(saf): implement Storage Access Framework (SAF) and Tree URI provider (F13) | palmoni5 |
| #70 | נסגר | יכולת חדשה | בידוד ואבטחה | — | מתנגש מול main | `.github/workflows/framework.yml`<br>`app/java/com/gesher/app/Main.java`<br>`app/java/com/gesher/server/ActivityTaskManagerService.java`<br>`app/java/com/gesher/server/ApkPackage.java`<br>ועוד 4 | feat(security): implement per-package identity and UID isolation (F07) | palmoni5 |
| #68 | נסגר | שינוי | שכבת POSIX | — | מתנגש מול main | `CMakeLists.txt`<br>`compat/posix/posix.cmake`<br>`compat/posix/src/epoll.cc`<br>`compat/posix/src/fd.cc`<br>ועוד 3 | compat: implement POSIX pipe semantics, O_NONBLOCK, backpressure and epoll readiness | palmoni5 |
| #67 | נסגר | יכולת חדשה | לוח העתקה | — | מתנגש מול main | `.github/workflows/clipboard-access.yml`<br>`.github/workflows/framework.yml`<br>`app/java/com/gesher/app/Main.java`<br>`app/java/com/gesher/server/ActiveServices.java`<br>ועוד 25 | feat(server): enforce Android 10+ clipboard focus and default IME contract (F37) | palmoni5 |
| #54 | נסגר | שינוי | מצלמה | — | מתנגש מול main | `app/java/android/app/GesherActivityWindow.java`<br>`app/java/com/gesher/server/CameraDeviceUser.java`<br>`app/java/com/gesher/server/CameraSelection.java`<br>`app/java/com/gesher/server/CameraService.java`<br>ועוד 10 | Camera/sensor check scanning support and Bionic REG_NEWLINE/escape fixes | ztcebuck |

## ללא תוכן מוצר — פיילוט CI עם היסטוריה נפרדת

| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |
|---|---|---|---|---|---|---|---|---|
| #183 | נסגר | תשתית CI | תשתית CI ובדיקות | — | ללא היסטוריה משותפת | — | CI gate runner pilot (fail fixture) | palmoni5 |
| #182 | נסגר | תשתית CI | תשתית CI ובדיקות | — | ללא היסטוריה משותפת | — | CI gate runner pilot (pass fixture) | palmoni5 |

## PRs שמוזגו ל-main אחרי v0.2.0 (ייכנסו אצלנו אוטומטית)

אלה תיקונים ויכולות שכבר נמצאים ב-main של upstream אבל לא בגרסה 0.2.0 שהמשתמשים מורידים. בגלל זה חלק גדול מהבאגים שדווחו כבר פתורים בקוד ועדיין מופיעים אצל המשתמשים.

| PR | כותרת |
|---|---|
| #486 | docs(policy): allow maintainer-approved missing-PC-capability adaptations (#486) |
| #482 | feat(panel): add "Open logs location" to the Control Center (#482) |
| #481 | Fix app install and run failures from #426: android.test libraries, shell and exec tools, dlopen messages (#481) |
| #477 | fix(signals): deliver tgkill/tkill to other threads (Chrome's stack sampler) (#477) |
| #476 | fix(net): expose roots installed on this PC as user-added CAs (Chrome behind NetFree) (#476) |
| #474 | fix(gles): advertise OpenGL ES 3.0, and keep it true on every adapter (#474) |
| #462 | docs: refresh UI presentation validation after merge (#462) |
| #460 | fix(posix): answer SYNC_IOC_FILE_INFO on native fence descriptors (#460) |
| #459 | fix(bionic): implement mallopt over the CRT heap (#459) |
| #458 | fix(elf): honour android_dlopen_ext's reserved address (Chrome) (#458) |
| #457 | fix: report the WebView provider, GNSS and real camera autofocus (#457) |
| #453 | fix(media): show Flutter platform views by drawing into PRIVATE ImageReaders (fixes #423) (#453) |
| #449 | fix(renderscript): run android.renderscript on libRS's CPU runtime (#449) |
| #448 | fix(accounts): let clients that see an account read its previous name (#448) |
| #447 | perf(media,webview,settings): reuse buffers with correct output and lifetime contracts (#447) |
| #446 | fix(installer): ignore unrelated split APKs in same directory (fixes #383) (#446) |
| #445 | fix(posix): normalize DLL paths and retain no-load references (#445) |
| #444 | fix(hwui): decode images from file descriptors (#444) |
| #443 | fix(launch, bidi): localize ABI mismatch failures and protect LTR errors (#443) |
| #442 | Install app bundles as Android would: content detection, bundletool APK sets, XAPK manifests (#442) |
| #439 | feat(package): add portable installation mode and zip packaging (fixes #417) (#439) |
| #438 | fix(window): close a single-process Activity that finishes before its Win32 window exists (#438) |
| #422 | Separate desktop presentation from action and window control logic (#422) |
| #409 | ci: receive the core supplier batch once and wait for reachable quota resets (#409) |
| #406 | fix(a11y): skip WebView snapshots abandoned before they start (#406) |
| #399 | perf(gfx,usage): preserve surface damage and implement visible usage observers (#399) |
| #398 | fix(media): scope native audio JNI attachment and validate speech/lock contracts (#398) |
| #395 | Verify retained E2E installer uploads from the original execution (#395) |
| #387 | camera,sensors: sync sensor orientation to display rotation and add tabletop accelerometer fallback (#387) |
| #386 | Report activity process death before launch readiness (#386) |
| #385 | Support APKM and APK+ split packages in Windows (#385) |
| #381 | fix(posix,media,bluetooth,ime): memfd write leases, event-driven media/WASAPI, API 37 RFCOMM EOF & bounded SDP (#381) |
| #377 | ci: call framework.yml as a local reusable workflow (#377) |
| #371 | Pin TCP rerun entry baselines to canonical history (#371) |
| #369 | Grant the automerge token Issues write access (#369) |
| #368 | Merge pull request #368 from gesher-runtime/codex/preserve-pending-activity-launch |
| #367 | fix(store): install Aurora Store 4.8.4 (#367) |
| #366 | feat(auth): Windows Hello backend for device-credential confirmation (ADR 0091, phase 2; stacked on #340) (#366) |
| #334 | Fix WASAPI playback across Android stream groups (#334) |
| #333 | fix(window): say which Windows call refused a window and its error (#333) |
| #331 | Merge pull request #331 from gesher-runtime/fix/log-triage-small |
| #330 | fix(launch): complete am start -W on the first frame drawn, not only idle (#330) |
| #329 | fix(broadcast): action-less receiver filters as Android 16 registers and resolves them (Waze) (#329) |
| #327 | fix(app): BluetoothDevice.prepareToEnterProcess and a manager-less usb service (Baseus) (#327) |
| #326 | fix(bluetooth): stop a never-started BLE scan without BLUETOOTH_SCAN, as Android (#326) |
| #325 | Fix Leumi provider startup and export Bionic execl (#325) |
| #324 | Merge pull request #324 from gesher-runtime/codex/fix-aliexpress-startup |
| #323 | Merge pull request #323 from gesher-runtime/feat/appcontainer-sandbox-poc |
| #321 | ci: authenticate retained producers for ordinary job reruns (#321) |
| #317 | Merge pull request #317 from tsoolgee/control-panel-proxy |
| #315 | fix(credentials): give the permission dialog Gesher's icon (#315) |
| #313 | fix(posix): identify files on volumes without FileIdInfo (#313) |
| #311 | fix(microg): keep an installed app of another signer instead of failing startup (#311) |
| #309 | perf(posix): route local inotify writes by watched file identity (#309) |
| #308 | fix(app): keep ART's stderr diagnostics from failing gesher-app actions (#308) |
| #307 | installer: skip optional downloads that fail instead of blocking Setup (#307) |
| #302 | perf(textservices): share owned spell-checker provider bindings (#302) |
| #300 | perf(bitmap): retain shared pixel storage across Parcel transfers (#300) |
| #299 | perf(net): reuse owned HTTP/2 sessions with correct receive credit (#299) |
| #298 | fix(shortcuts): enforce API quotas with owned foreground exemptions (#298) |
| #297 | perf(posix): retire virtual epoll watches by shared file owner (#297) |
| #295 | feat(server): add SQLite ContactsProvider for com.android.contacts (#295) |
| #294 | Implement MP4 recording rollover without recreating capture or encoders (#294) |
| #293 | fix(posix): publish timerfd and inotify epoll edges without idle repeats (#293) |
| #291 | perf(usage): select event ranges before copying query snapshots (#291) |
| #288 | fix(jobs): bound fresh content-trigger batches and preserve retries (#288) |
| #287 | Implement reusable persistent input Surfaces for codec and recorder (#287) |
| #286 | perf(net): bound UrlRequest read scratch allocation (#286) |
| #285 | ci: authenticate separate fork TCP supplier diagnostics (#285) |
| #284 | fix(jobs): enforce per-UID scheduled-job admission bounds (#284) |
| #283 | Add Photo Picker ACTION_PICK_IMAGES, ACTION_CHOOSER document delegation, and full MimeMap (#283) |
| #282 | feat(net): honor private HttpEngine HTTP cache modes (#282) |
| #281 | ci: authenticate isolated fork DNS diagnostics (#281) |
| #280 | Implement MediaCodec fit/crop scaling in display consumers (#280) |
| #279 | perf(bionic): reuse regex epsilon closures and stop boolean matches early (#279) |
| #277 | perf(pm): index intent candidates by package generation (#277) |
| #267 | perf(notifications): prepare owned large icons outside publication fence (JAVA-07) (#267) |
| #264 | audio: enforce live UID microphone admission (F09) (#264) |
| #263 | perf(logging): bound tag-priority caching and remove warm record allocations (NATIVE-13) (#263) |
| #262 | camera: enforce runtime permission on Camera2 and legacy opens (C07) (#262) |
| #257 | fix(uia): wake canceled queries while retaining active worker ownership (#257) |
| #255 | perf(dns): bound Java resolver admission and completion ownership (#255) |
| #252 | perf(media): render retriever frames with bounded target-size rows (#252) |
| #251 | Merge pull request #251 from gesher-runtime/palmoni5/issue178-java03-host-events |
| #250 | Merge pull request #250 from gesher-runtime/palmoni5/issue178-native10-dns |
| #248 | ui: unify Gesher host dialogs with the Control Center design (#244) (#248) |
| #247 | perf(dexopt): schedule profile work with foreground budgets (START-03) (#247) |
| #243 | camera: bound Camera2 request and callback admission (MEDIA-06) (#243) |
| #236 | fix(jni): reject unbridged GetEnv interfaces before host lookup (#236) |
| #235 | perf(webview): reuse geometry scratch and preserve nested updates (JAVA-08) (#235) |
| #233 | perf: quiesce hidden Control Center metadata scans (#233) |
| #231 | test(shell): publish immutable owned splash receipts (#231) |
| #230 | perf: establish reproducible A/B measurement and owned Windows evidence (#230) |
| #229 | fix(providers): handle authenticated unstable provider death reports (#229) |
| #228 | tools: compare service overrides by exact JVM descriptor and owner (#228) |
| #227 | permissions: preserve runtime denial and rationale state (F09) (#227) |
| #191 | feat(server): add SQLite CallLogProvider and contacts provider plumbing (#191) |
| #113 | Add shared pthread CPU clock provider prerequisite (N28) (#113) |
| #78 | test(chooser): preserve owned task admission after main integration (#78) |
| #75 | feat(services): enforce exact alarm scheduling contracts and permissions (F28) (#75) |
| #74 | feat(storage): implement persistable URI grants across runtime lifecycles (F11) (#74) |
| #73 | compat: implement file status flags and open file description semantics (N32) (#73) |
