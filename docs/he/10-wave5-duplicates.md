# 10 — גל 5: בדיקת כפילויות של ה-PRs שנסגרו

**תאריך:** 27.11.2026. **מצב:** נבדקו כל 44 ה-PRs של גל 5, מול `product` בקומיט `f978355bb` (העץ של גרסה 1.2.0).

## מה נבדק, ובאיזו שיטה

גל 5 הוא PRs שנסגרו בלי מיזוג (רובם של palmoni5), והם מתנגשים מול `main`. השאלה לכל אחד: האם התוכן שלו נכנס בדרך אחרת, בדרך כלל דרך PR מאחד כמו #212–#215 ו-#218, ומה חסר.

1. **שורות שכבר קיימות:** לכל PR נספרו השורות שהוא מוסיף (יותר מ-12 תווים) שכבר קיימות באותו קובץ ב-`product`. היחס מופיע בעמודה האחרונה.
2. **קבצים חדשים:** לכל קובץ חדש של ה-PR נבדק באיזה קומיט ב-`main` הוא נוסף לראשונה, ולכן איזה PR הכניס אותו.
3. **קומיט-קומיט:** לכל קומיט בכל PR נבדק אם יותר מ-30% משורותיו חסרות ב-`product`. נמצאו 29 קומיטים כאלה ב-16 PRs. לכל PR שהופיע ברשימה בדקתי מול הקוד אם התכונה קיימת ב-`product`, בצורה זהה או בצורה אחרת. זו בדיקה נקודתית של התכונה, לא השוואה של כל קומיט לקומיט (התוצאה בטבלה).

## התוצאה

| תוצאה | מספר PRs |
|---|---|
| כבר ב-product | 32 |
| הוחלף במימוש אחר | 5 |
| נעיצות ותשתית CI | 6 |
| **פער: לא נכנס** | **1** |

**אין אף PR בגל 5 שצריך להיכנס לתור כמו שהוא.** ‏43 מתוך 44 כבר בפנים, או הוחלפו במימוש מאוחר יותר, או שהם רק נעיצות. הפער היחיד הוא #234.

## הפער: #234, זמן CPU של תהליכי ילד

‏#234 רושם את זמן ה-CPU האמיתי של ילדים ישירים של המתאם הנייטיב (Bionic) ושל המתאם של Java (libcore), כדי ש-`getrusage(RUSAGE_CHILDREN)` ו-`times` יחזירו ערכים אמיתיים. ב-`product` עדיין כתוב ב-`extra_sys_bionic.cc` וב-`process.cc` שזמני הילדים לא נאספים, והם מוחזרים כאפס.

**למה לא נכנס עכשיו:** ניסיתי למזג אותו על `product-candidate` (ענף נושא נפתח ונסגר, בלי קומיט). ארבעה קבצים בהתנגשות: שניים של CI (`ci.yml`, ‏`exec.yml`) ושורות `#include` ב-`process.cc`, שאיחדתי בלי בעיה, ו-`process_bionic.cc` עם 6 מקטעים מהותיים. ‏`process_bionic.cc` כתוב מחדש מאז ש-#234 נכתב: #478 הוסיף fork ו-clone אמיתיים, אות יציאה לכל ילד, ‏`Eligible` ל-`__WCLONE` ו-`__WALL`, וחוט עזר לכל ילד של תהליך משוכפל. המנגנון של #234 (אסימון דור לכל ילד, ‏`ChildWatch` עם ספירת הפניות, ומסירה ל-`wait4` תחת נעילה) לא נכנס מעל זה בלי תכנון מחדש.

בנוסף, הבדיקות של #234 (`tools/test_child_usage_contracts.py`, ‏`tests/exec/child_usage_contracts.cc.in`) מחלצות את גבולות הייצור מהקבצים האלה, וקוראות ישירות ל-`guest::Track` ול-`guest::g_children`. ‏בלי כתיבה מחדש של הבדיקות הן לא יעברו, וההרצה שלהן אפשרית רק ב-CI של Windows.

**מה צריך:** הוספת `usage_token` ל-`Child` של `product`, רישום ב-`Track` ואיסוף ב-`CollectOne` מעל המבנה הנוכחי (כולל ילדי fork), התאמה של מתאם ה-Java, וכתיבה מחדש של הבדיקות. ההערכה: עבודה ייעודית, עם ריצת CI שלמה לפחות. **מדווח כאן כפער ידוע:** במרשם הבאגים אין דיווח שתלוי בזה (חיפוש `getrusage` ו-`RUSAGE` לא מצא כלום).

### ניסיון שני (28.11.2026): נעצר לפני כתיבת קוד, ומה נמצא

פתחתי שוב ענף נושא (`topic/pr-234` מעל `product` של 1.2.1, ללא קומיט, ולא נדחף) וקראתי את `process_bionic.cc` של `product` לעומק לפני שנגעתי בו. מה שנמצא, והסיבה שהפורט **לא בוצע**:

- **חלק מהפער כבר סגור.** ‏`CollectOne` של `product` כבר ממלא את `rusage` של `wait4` לכל ילד (`FillRusage`: ‏`GetProcessTimes` ועוד מונה זיכרון: ‏`maxrss`, ‏`minflt`). הפער האמיתי הוא רק הסכום המצטבר: ‏`getrusage(RUSAGE_CHILDREN)` ו-`times` מחזירים אפסים, וילדים שמתחילים דרך Java (`libcore/process.cc`) לא נספרים בשום מקום.
- **ה-fork של #478 סותר את הספר של #234.** ‏`GuestFork` משכפל את מרחב הכתובות (`CloneProcess`) תחת "קבוצת מנעולי fork" (`AcquireForkLocks`), ו-`ForkChildProcessState` מנקה בילד את `g_children` ואת הידיות של ילדי האב. הספר של #234 חי בקובץ ההרצה, עם `SRWLOCK`, רשימת רשומות עם ידיות מוחזקות וסכום מצטבר. בילד משובט הוא יועתק כמו שהוא, ובלינוקס הסכום של ילד כזה מתחיל מאפס. לכן צריך (א) שהמנעול של הספר יהיה חלק מקבוצת המנעולים של ה-fork, כדי שיהיה עקבי בילד, (ב) פעולת איפוס שנקראת מ-`ForkChildProcessState`, ו-(ג) בדיקות לתרחישי fork. ‏#234 נכתב לפני #478 (המסמך שלו אומר שמסלול ה-fork הסינתטי "שייך ל-PRs הממתינים"), ולכן שום חלק מזה לא נבדק בו. לא בדקתי איזה ידיות בדיוק מקבל הילד המשובט, ולכן גם לא ברור אם סגירה של הידיות המוחזקות שם בטוחה.
- **גרסה חלקית לא באה בחשבון.** אפשר היה לספור רק ילדים של המתאם הנייטיב, במשתנה גלובלי בלי הספר המשותף, אבל אז `getrusage(RUSAGE_CHILDREN)` היה מחזיר סכום שחסרים בו ילדי Java, כאילו הוא שלם. המדיניות של #234 עצמו היא הפוכה: סכום חלקי מדווח כלא זמין ולא כמספר. זה גם עיקרון התוצאות הכנות של הפרויקט.

**מה נדרש:** תכנון שמחבר את הספר ל-fork (מנעול בקבוצה, איפוס בילד), התאמה של ה-`Track` ושל כל הקוראים שלו (`SpawnPrepared` וקריאת ה-clone), כתיבה מחדש של הבדיקות מול המבנה של #478 (כולל ה-stubs של פונקציות ה-fork בבדיקה שמחלצת קוד ייצור), וריצת CI מלאה על Windows. הוא נשאר פער ידוע, בלי באג תלוי.

## כל ה-PRs

| PR | כותרת | תוצאה | איפה | יחס שורות שכבר ב-product |
|---|---|---|---|---|
| #400 | Telephony over a Windows cellular modem (read-only, data-only) | כבר ב-product | הקבצים החדשים כולם נכנסו ב-#421. שני תיקוני הסיום: `requestCellInfoUpdate` קיים ב-`TelephonyService.java`; מצב ה-SIM בלי מודם נקבע שם אחרת במכוון ("superseding ADR 0087's ABSENT"). רק מסמך ההחלטה `docs/decisions/0091` לא נכנס | 93% |
| #397 | Report FEATURE_SENSOR_* for the sensors SensorManager lists | כבר ב-product | ‏#421. הקוד ב-`PackageManagerService.java` והבדיקה ב-`PackageServiceQueriesTest.java` | 82% |
| #396 | Report the system features Windows backs; declare OpenGL ES 3.0 | כבר ב-product | ‏#421, ו-#474 (OpenGL ES 3.0) | 83% |
| #388 | fix: complete round 1 compatibility and performance work from #381 | כבר ב-product | ‏#381 (8 קבצים חדשים) | 97% |
| #378 | test(alarms): retire owned policy writes before #325 fixture cleanup | נעיצות ותשתית CI | שכבת נעיצה של שרשרת ה-TCP (`ofd-stream-source.json`), ושני תיקוני כינויי ספקים שהלוגיקה שלהם קיימת בצורה אחרת ב-`ApkPackage.java`. שוויון ההתנהגות לא נבדק | 96% |
| #346 | ci: pin framework.yml to a commit on main | נעיצות ותשתית CI | נעיצת `framework.yml` לקומיט ב-upstream. מיושן: הנעיצות מופקות מחדש אצלנו עם הכלים של הפרויקט | 0% |
| #292 | ci: repin the framework recipe to a commit reachable from main | נעיצות ותשתית CI | כמו #346 | 0% |
| #234 | posix: account reaped direct-child CPU across native and Java (N38) | פער: לא נכנס | חישוב זמן CPU אמיתי של תהליכי ילד (`getrusage(RUSAGE_CHILDREN)`, ‏`times`). ב-product עדיין "children's times are not collected". פירוט בסעיף הפער | 0% |
| #225 | tests: keep clipboard foreground helper on harness PowerShell | הוחלף במימוש אחר | הקובץ `tests/windows/clipboard/ForeignForeground.ps1` כבר לא קיים: #226 ו-#363 (ב-product) החליפו את עזר ה-foreground של הלוח | 0% |
| #223 | [Validation only] Correct authenticated system identity in #198 Bluetooth CI f | הוחלף במימוש אחר | טיוטת בדיקה בלבד. ‏5 הקבצים החדשים נכנסו ב-#198, וטיפול הבקשות ב-`BluetoothRequests.java` | 97% |
| #222 | Repair and verify Bluetooth request intents from #198 | הוחלף במימוש אחר | כמו #223 | 97% |
| #210 | feat(memfd): store and enforce memfd seals; ASharedMemory as libcutils' memfd  | כבר ב-product | ‏#212 | 85% |
| #209 | feat(socket): AF_UNIX socketpair credentials (ADR 0088, phase 1) | כבר ב-product | ‏#212 | 90% |
| #208 | docs(adr): AF_UNIX credentials and descriptor passing (0088, proposed) | כבר ב-product | מסמך החלטה (טיוטה), כמעט זהה ל-product | 99% |
| #206 | fix(bionic): export fnmatch to loaded libraries, with bionic's flag values | כבר ב-product | 100% מהשורות ב-product | 100% |
| #205 | fix(jni): know a JNIEnv proxy by its identity, not by its table | כבר ב-product | 100% מהשורות ב-product | 100% |
| #203 | fix(posix): report sysname "Linux" from uname, as Android does | כבר ב-product | ‏#212 | 100% |
| #202 | ci: overlap builds with preflight, split the media shard and save caches only  | כבר ב-product | ‏#213 ו-#215 | 99% |
| #201 | fix(providers): bind and validate each provider component once | כבר ב-product | ‏#212 | 96% |
| #200 | fix(permission): ship android.safetycenter so the Play Store survives package  | כבר ב-product | ‏#212 (20 קבצים חדשים) | 100% |
| #195 | ci: cut GITHUB_TOKEN REST calls and wait for quota resets instead of failing | נעיצות ותשתית CI | ‏#199 לקבצים החדשים. מה שנשאר: נעיצות מקורות, ושינויים צרים בקריאות ה-API של ה-CI | 88% |
| #192 | ci: recover stuck automerge gates; make the legacy QA gate optional once the A | נעיצות ותשתית CI | ‏#213 ו-#215. אצלנו הבוט האוטומטי כבוי ממילא | 89% |
| #163 | Implement Wi-Fi channel and blocking option value contracts (A02) | כבר ב-product | ‏#214 | 100% |
| #159 | Implement Wi-Fi Direct discovery and USD value contracts (A02) | כבר ב-product | ‏#154, ‏#214, ‏#144 | 100% |
| #150 | Implement SDK36 Wi-Fi Direct value contracts (A02) | כבר ב-product | ‏#154 ו-#144 | 100% |
| #148 | Implement WifiNetworkSuggestion and Passpoint value contracts (A02) | כבר ב-product | ‏#214 | 100% |
| #146 | Propagate capture availability and disconnect errors across Android APIs | כבר ב-product | ‏#111. גם בדיקות ה-AAudio קיימות | 96% |
| #145 | Preserve notification ownership when migrating Windows toast identities | כבר ב-product | ‏#139 | 96% |
| #142 | Separate colliding notification records and images safely | כבר ב-product | ‏#139 | 94% |
| #141 | Implement WifiNetworkSpecifier value and matching contracts (A02) | כבר ב-product | ‏#214 | 100% |
| #136 | Release completed WebView geolocation timeouts | כבר ב-product | ‏#214 | 100% |
| #131 | fix(bionic): implement binary128 parsing and ARM64 numeric returns (N39) | כבר ב-product | ‏#213 ו-#199 | 100% |
| #128 | test(arm64): qualify native callback cleanup and preserve failure baseline (N1 | כבר ב-product | ‏#213 ו-#199 | 98% |
| #125 | ci: refresh reviewed source identity helper pins | נעיצות ותשתית CI | נעיצות של עזר הזהות. מופקות מחדש בכלי הפרויקט | 50% |
| #123 | fix(arm64): add Windows unwind metadata for native ABI thunks (N15/N18) | כבר ב-product | ‏#199 | 99% |
| #116 | Implement persistent Android user extended attributes (N42) | כבר ב-product | ‏#124 | 93% |
| #106 | Support installed Android spell checkers and their Binder sessions (F38) | כבר ב-product | ‏#218 | 97% |
| #104 | media: implement live AVC bitrate control and MediaCodec metrics (M05) | כבר ב-product | ‏#218 | 97% |
| #94 | media: preserve MediaCodec output surface timestamps (M18) | כבר ב-product | ‏#218 | 95% |
| #71 | feat(saf): implement Storage Access Framework (SAF) and Tree URI provider (F13 | כבר ב-product | ‏#72 (28 קבצים חדשים). ב-product: `DocumentsStorageProvider`, ‏`UriGrants`, ‏`IntentChooser` | 98% |
| #70 | feat(security): implement per-package identity and UID isolation (F07) | כבר ב-product | ‏#72. ב-product: `PackageUids`, ‏`CallerIdentity` | 97% |
| #68 | compat: implement POSIX pipe semantics, O_NONBLOCK, backpressure and epoll rea | הוחלף במימוש אחר | מימוש חלופי ל-pipe (`pipe.cc`). ב-product כבר יש `pipe_io.cc` עם PIPE_BUF, ‏O_NONBLOCK ולחץ חוזר (נכנס עם #118), ועם בדיקות. שני מימושים היו מתנגשים ב-`epoll.cc`, ‏`fd.cc`, ‏`system.cc` ו-`unistd.cc` | 0% |
| #67 | feat(server): enforce Android 10+ clipboard focus and default IME contract (F3 | כבר ב-product | ‏#213 ו-#72. ב-product: `AppOpsService`, ‏`AppOpsModeStore` | 96% |
| #54 | Camera/sensor check scanning support and Bionic REG_NEWLINE/escape fixes | הוחלף במימוש אחר | ‏#487 ו-#121. מקור התמונה של המצלמה קיים כ-`CameraSourceService` ו-`CameraImageSource`. ‏`REG_NEWLINE` כבר ב-`posix_regex.h` | 19% |

## מה לא נבדק

- **לא הרצתי את הבדיקות של ה-PRs הישנים מול `product`.** כל הקביעות לפי טקסט הקוד, ההיסטוריה של `main` ובדיקות נקודתיות שהן מופיעות בטבלה. ‏"כבר ב-product" פירושו שהתוכן קיים, ולא שההתנהגות זהה בכל פרט.
- **יחס שורות נמוך אינו פער.** ב-#54, ‏#234 וב-#68 היחס נמוך. ב-#54 וב-#68 התברר שהקוד הוחלף במימוש אחר (בדיקה ידנית), וב-#234 הוא פער אמיתי.
- **#378:** לא נבדק ששני תיקוני כינויי הספקים שלו שקולים להתנהגות הנוכחית של `ApkPackage.java`.
