"""בונה את מרשם ה-PRs (docs/he/04-pr-register.md) מתוצאות הסימולציה.

קלטים (בתיקיית העבודה שמועברת כארגומנט):
  prs.json            - פלט classify_prs.py: כל ה-PRs, מצב לפי git, היקף שינוי
  merge_sim.json      - פלט simulate_merges.py: מיזוג כל PR בנפרד מול main
  waves_seq.json      - פלט sequential_sim.py: מי נכנס ברצף בלי התנגשות
  pr_web.tsv          - צילום רשימות ה-PRs הפתוחים והסגורים מהאתר
  merged_after_020.txt - מספרי PRs שמוזגו ל-main אחרי v0.2.0

שימוש:
  python3 -I tools/integration/build_pr_register.py <תיקיית-נתונים> <קובץ-פלט>
"""
import json
import re
import sys

data_dir, out_path = sys.argv[1], sys.argv[2]

web = {}
for line in open(f"{data_dir}/pr_web.tsv", encoding="utf-8"):
    n, state, author, labels, title = line.rstrip("\n").split("\t", 4)
    web[int(n)] = dict(state=state, author=author, labels=labels, title=title)
sim = {int(x["name"][1:]): x for x in json.load(open(f"{data_dir}/merge_sim.json", encoding="utf-8"))
       if x["name"].startswith("#")}
lev_sim = [x for x in json.load(open(f"{data_dir}/merge_sim.json", encoding="utf-8"))
           if x["name"].startswith("lev")]
prs = {r["n"]: r for r in json.load(open(f"{data_dir}/prs.json", encoding="utf-8"))}
seq = json.load(open(f"{data_dir}/waves_seq.json", encoding="utf-8"))
seq_ok = {int(x[1:]) for x in seq["ok"]}
seq_fail = {int(x[1:]) for x in seq["fail"]}
after020 = [int(x) for x in open(f"{data_dir}/merged_after_020.txt").read().split()]

# PRs שקשורים ישירות לבאגים או לבקשות שדווחו ב-issues (גל 1)
ISSUE_LINKS = {
    328: [355], 454: [355], 332: [310, 312, 322, 431], 414: [407], 421: [463],
    432: [301], 484: [301, 480], 491: [472], 464: [335], 340: [339], 470: [339],
    471: [339], 475: [339], 427: [314], 493: [364], 455: [304, 316],
    402: [375], 403: [375],
}

TYPE_HE = [
    (r"^perf", "ביצועים"), (r"^fix", "תיקון"), (r"^feat", "יכולת חדשה"),
    (r"^test", "בדיקות"), (r"^ci", "תשתית CI"), (r"^docs", "תיעוד"),
    (r"^ui", "ממשק"), (r"^(media|net|bionic|posix|compat|sensors|services|wifi|camera|audio|server)\b", "שינוי"),
]
AREA_HE = [
    (r"control-panel|control center|ui:|messagebox|dialog|bidi", "ממשק ומרכז הבקרה"),
    (r"media|codec|avc|hevc|mp3|vorbis|opus|imagereader|i420|nv12|resampl|mp4|annex", "מדיה"),
    (r"audio|wasapi|opensl|voice call", "שמע"),
    (r"camera", "מצלמה"),
    (r"bionic|scandir|snprintf|stdio|pthread|wide conversion|libstdc|fnmatch|binary128|\bselect(impl)?\b", "ספריית C (bionic)"),
    (r"posix|mkfifo|fifo|ptrace|uname|mman|memfd|pipe|xattr|extended attributes|cpu across", "שכבת POSIX"),
    (r"arm64|tls pages|fork and clone", "תרגום arm64"),
    (r"wi-?fi|passpoint|softap|wps", "Wi-Fi"),
    (r"nsd", "גילוי שירותים ברשת (NSD)"),
    (r"dns|http|brotli|net:|net\(|netlink|socks|proxy|connectivity|metered|socket|trust|certificate", "רשת"),
    (r"auth|keystore|credential|passkey|hello|biometric", "אימות ואבטחה"),
    (r"appcontainer|sandbox|identity and uid|uid isolation", "בידוד ואבטחה"),
    (r"gms|play services|microg|play games|accountmanager|accounts|authenticator", "חשבונות ושירותי Google"),
    (r"package|pm\)|pm:|uid owner|visibility|dexopt|profman|component families|installer", "ניהול חבילות והתקנה"),
    (r"sensor", "חיישנים"),
    (r"telephony|cellular", "טלפוניה"),
    (r"bluetooth", "בלוטות'"),
    (r"\busb\b|cardwake", "USB"),
    (r"window|multi-window|freeform|display", "חלונות"),
    (r"notification|toast", "התראות"),
    (r"clipboard", "לוח העתקה"),
    (r"print", "הדפסה"),
    (r"tts|text-to-speech|speech", "דיבור"),
    (r"caption|accessibility", "נגישות"),
    (r"location|country|geolocation", "מיקום"),
    (r"intent|mailto|shortcut|broadcast", "אינטנטים וקיצורי דרך"),
    (r"downloads|mediastore|content://media|saf|storage|sqlite|userdictionary", "אחסון וספקי תוכן"),
    (r"binder|transactions", "Binder"),
    (r"elf|symbol versions|classloader namespaces|native", "ספריות נייטיב"),
    (r"jni", "JNI"),
    (r"alarm|jobscheduler|appops|statusbar|foreground|thermal", "שירותי מערכת"),
    (r"logging|redact", "יומנים ופרטיות"),
    (r"identity|manufacturer|pixel", "זהות המכשיר"),
    (r"spell", "בודק איות"),
    (r"smtc|mediasession", "מדיה"),
    (r"webview", "WebView"),
    (r"ci|automerge|github|sponsors|framework\.yml|framework recipe|gate|runner|cache|quota|pins|fixture", "תשתית CI ובדיקות"),
    (r"roadmap|round 1|round 2|cumulative|integration", "אינטגרציה מצטברת"),
]


def type_he(title):
    t = title.lower()
    for pat, label in TYPE_HE:
        if re.search(pat, t):
            return label
    return "שינוי"


def area_he(title):
    t = title.lower()
    for pat, label in AREA_HE:
        if re.search(pat, t):
            return label
    return "כללי"


VERDICT_HE = {
    "clean": "נכנס נקי מול main",
    "conflict": "מתנגש מול main",
    "already-in-main": "התוכן כבר ב-main",
    "error": "ללא היסטוריה משותפת",
}


def wave(n, w, s):
    v = s.get("verdict")
    if v == "already-in-main" or n == 15:
        return 0
    if v == "error":
        return 9
    if n in ISSUE_LINKS:
        return 1
    if n in seq_ok:
        return 2
    if n in seq_fail:
        return 3
    if w["state"] == "open":
        return 4
    return 5


WAVE_HE = {
    0: "גל 0 — כבר בפנים (אין מה למזג)",
    1: "גל 1 — תיקונים לבאגים ולבקשות שדווחו",
    2: "גל 2 — נכנסים ברצף בלי שום התנגשות",
    3: "גל 3 — נקיים מול main אבל מתנגשים זה בזה",
    4: "גל 4 — פתוחים שמתנגשים מול main",
    5: "גל 5 — סגורים שמתנגשים מול main (נבדק כפילות מול PRs מאחדים)",
    9: "ללא תוכן מוצר — פיילוט CI עם היסטוריה נפרדת",
}

rows = []
for n, w in web.items():
    s = sim.get(n, {})
    p = prs.get(n, {})
    rows.append(dict(n=n, w=w, s=s, p=p, wave=wave(n, w, s)))

lines = []
A = lines.append
A("# מרשם ה-PRs — כל מה שלא מוזג ל-upstream")
A("")
A("> מסמך שנוצר אוטומטית על ידי `tools/integration/build_pr_register.py`. אל תערכו אותו ידנית — עדכנו את הנתונים והריצו שוב.")
A("")
A("**נקודת ייחוס:** `gesher-runtime/gesher` main בקומיט `669d40a12` (25.11.2026). "
  "סימולציית המיזוג רצה עם `git merge-tree --write-tree` — בלי לגעת בקוד, רק בדיקה אם המיזוג נקי ואילו קבצים מתנגשים.")
A("")
A("## תמונת מצב")
A("")
total = len(prs)
merged = sum(1 for r in prs.values() if r["state"] == "merged") + (1 if 9 in prs and prs[9]["state"] != "merged" else 0)
A("| מדד | מספר |")
A("|---|---|")
A(f"| סך כל ה-PRs שנפתחו ב-upstream | {total} |")
A(f"| מוזגו ל-main | {total - len(web)} |")
A(f"| מתוכם מוזגו אחרי v0.2.0 ועדיין לא שוחררו למשתמשים | {len(after020)} |")
A(f"| פתוחים (ממתינים לאישור) | {sum(1 for w in web.values() if w['state'] == 'open')} |")
A(f"| נסגרו בלי מיזוג | {sum(1 for w in web.values() if w['state'] == 'closed')} |")
A(f"| ענפים ייחודיים בפורק Lev-Good | 1 (`fix/app-compat`, 7 קומיטים) |")
A("")
A("### חלוקה לגלי אינטגרציה")
A("")
A("| גל | מספר PRs | פתוחים | סגורים |")
A("|---|---|---|---|")
for k in sorted(WAVE_HE):
    rs = [r for r in rows if r["wave"] == k]
    if not rs:
        continue
    A(f"| {WAVE_HE[k]} | {len(rs)} | {sum(1 for r in rs if r['w']['state'] == 'open')} | "
      f"{sum(1 for r in rs if r['w']['state'] == 'closed')} |")
A("")
A("### הקבצים שמתנגשים הכי הרבה (מול main)")
A("")
from collections import Counter
cf = Counter(f for r in rows for f in r["s"].get("conflicts", []))
A("| קובץ | מספר PRs שמתנגשים בו |")
A("|---|---|")
for f, k in cf.most_common(12):
    A(f"| `{f}` | {k} |")
A("")
A("## פורק Lev-Good")
A("")
for x in lev_sim:
    A(f"- ענף `fix/app-compat` (כולל את התג `v0.2.0-lev1`): **{VERDICT_HE.get(x['verdict'], x['verdict'])}**, "
      f"{x['n_conflicts']} קבצים מתנגשים: " + ", ".join(f"`{c}`" for c in x["conflicts"]))
A("- תוכן: תיקון `getPreviousName` ב-AccountManager (חופף חלקית ל-#448 שכבר מוזג), דילוג על authority מתנגש של ספק תוכן (בנק לאומי), "
  "כינוי לשירות START_1P של Play Games, פרוקסי SOCKS5 (גם PR #493), נתיבי profman לשם משתמש בעברית (גם PR #454, issue #355), "
  "mkfifo עבור Realm, מחוון הפעלה ולוגים במתקין, ועיצוב מחדש של מרכז הבקרה (פריסה דו-טורית + חיפוש חי).")
A("")
for k in sorted(WAVE_HE):
    rs = sorted((r for r in rows if r["wave"] == k), key=lambda r: -r["n"])
    if not rs:
        continue
    A(f"## {WAVE_HE[k]}")
    A("")
    A("| PR | מצב | סוג | תחום | issue קשור | תוצאת סימולציה | קבצים מתנגשים | כותרת מקורית | מחבר |")
    A("|---|---|---|---|---|---|---|---|---|")
    for r in rs:
        n, w, s = r["n"], r["w"], r["s"]
        st = "פתוח" if w["state"] == "open" else "נסגר"
        if w["labels"] == "draft":
            st += " (טיוטה)"
        iss = ", ".join(f"#{i}" for i in ISSUE_LINKS.get(n, [])) or "—"
        v = VERDICT_HE.get(s.get("verdict", ""), "—")
        conf = s.get("conflicts", [])
        conf_txt = "<br>".join(f"`{c}`" for c in conf[:4]) + (f"<br>ועוד {len(conf) - 4}" if len(conf) > 4 else "") if conf else "—"
        title = w["title"].replace("|", "\\|")
        A(f"| #{n} | {st} | {type_he(title)} | {area_he(title)} | {iss} | {v} | {conf_txt} | {title} | {w['author']} |")
    A("")

A("## PRs שמוזגו ל-main אחרי v0.2.0 (ייכנסו אצלנו אוטומטית)")
A("")
A("אלה תיקונים ויכולות שכבר נמצאים ב-main של upstream אבל לא בגרסה 0.2.0 שהמשתמשים מורידים. "
  "בגלל זה חלק גדול מהבאגים שדווחו כבר פתורים בקוד ועדיין מופיעים אצל המשתמשים.")
A("")
A("| PR | כותרת |")
A("|---|---|")
for n in sorted(after020, reverse=True):
    t = (prs.get(n, {}).get("main_title") or prs.get(n, {}).get("head_subject") or "").replace("|", "\\|")
    A(f"| #{n} | {t} |")
A("")
open(out_path, "w", encoding="utf-8").write("\n".join(lines))
print("נכתב:", out_path, "| שורות:", len(lines))
print(Counter(r["wave"] for r in rows))
