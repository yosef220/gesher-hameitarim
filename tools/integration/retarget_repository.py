"""מכוון לריפו שלנו את זהות הריפו במסלול המוצר: פרסום גרסאות ועדכונים.

רקע: ה-CI של upstream מזהה את "הריפו הרשמי" לפי השם ולפי המספר המזהה
שלו. הוא תוכנן כך שגם פורק בונה, בודק ומפיק מתקינים, במצב שנקרא
fork-diagnostic. רק פרסום גרסה רשמית, ומקור העדכונים שהתוכנה מושכת
ממנו, דורשים את הזהות הרשמית.

לכן משנים רק את מה שהמוצר שלנו צריך:
  - חישוב הגרסה ופרסום ה-release (tools/ci/release_version.py,
    publish-release.yml, שלב אימות התג ב-ci.yml)
  - מקור העדכונים של התוכנה (tools/package/gesher-update.ps1) והבדיקות שלו
  - הקישורים בתבנית ה-PR

כל השאר (תת-מערכות הראיות, מקורות מהימנים ונעיצות) נשאר בדיוק כמו
ב-upstream. הקבצים האלה מוגנים בבדיקות השוואה בייט-לבייט, ובריפו שלנו
הם רצים במצב fork-diagnostic, כמו שתוכנן.

הסקריפט מחליף גם זהויות קודמות של הריפו שלנו (PREVIOUS), כדי שמעבר
לריפו חדש ייעשה בפקודה אחת.

הסקריפט אידמפוטנטי: מריצים אותו שוב אחרי כל סנכרון עם upstream.

שימוש:
  python3 -I tools/integration/retarget_repository.py          # החלפה
  python3 -I tools/integration/retarget_repository.py --check  # רק בדיקה, יציאה 1 אם נשארו הפניות
"""
import re
import subprocess
import sys
from pathlib import Path

UPSTREAM_SLUG = "gesher-runtime/gesher"
UPSTREAM_ID = "1426153186"
# האותיות הקנוניות, כפי ש-GitHub מחזיר (חשוב להשוואות רגישות לאותיות)
OURS_SLUG = "yosef220/gesher-hameitarim"
OURS_ID = "1471523850"
# זהויות קודמות שלנו. yosef220/APK היה ריפו רגיל ולא Fork אמיתי, ולכן
# ה-CI של upstream לא הריץ בו את כל הבדיקות. עברנו ממנו ל-gesher-hameitarim.
PREVIOUS = [("yosef220/APK", "1471037894")]

REPLACED = [(UPSTREAM_SLUG, UPSTREAM_ID)] + PREVIOUS


def id_pattern(value):
    return re.compile(r"(?<![0-9])" + value + r"(?![0-9])")


ID_PATTERNS = [id_pattern(value) for _, value in REPLACED]

# כל כלל: נתיב, ואם יש — ביטוי רגולרי שמגביל את ההחלפה לשורות שתואמות לו
RULES = [
    ("tools/ci/release_version.py", None),
    (".github/workflows/publish-release.yml", None),
    # רק שלב אימות התג (שחרור גרסה), לא שורות הראיות של TCP שרצות במצב פורק
    (".github/workflows/ci.yml", re.compile(r"github\.ref_type == 'tag'")),
    ("tools/package/gesher-update.ps1", None),
    ("tests/windows/shell/UpdateChecks.ps1", None),
    ("tests/windows/shell/UpdateTransportChecks.ps1", None),
    ("tests/windows/shell/ControlPanelUpdateChecks.ps1", None),
    ("tests/windows/shell/PortableProfileChecks.ps1", None),
    (".github/pull_request_template.md", None),
    # הבדיקה שנועצת את תנאי אימות התג (מסלול השחרור). שורת ניתוב ה-runner של automerge לא משתנה
    (".github/scripts/test_automerge_workflows.py", re.compile(r"self\.assertEqual\(identity\['if'\]")),
]


def retarget_line(line):
    for slug, _ in REPLACED:
        line = line.replace(slug, OURS_SLUG)
    for pattern in ID_PATTERNS:
        line = pattern.sub(OURS_ID, line)
    return line


def retarget_text(text, line_filter):
    if line_filter is None:
        return retarget_line(text)
    lines = text.splitlines(keepends=True)
    return "".join(retarget_line(l) if line_filter.search(l) else l for l in lines)


def count_refs(text, line_filter):
    lines = text.splitlines() if line_filter is not None else [text]
    total = 0
    for l in lines:
        if line_filter is not None and not line_filter.search(l):
            continue
        total += sum(l.count(slug) for slug, _ in REPLACED)
        total += sum(len(p.findall(l)) for p in ID_PATTERNS)
    return total


def main():
    check = "--check" in sys.argv[1:]
    root = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                               text=True, check=True).stdout.strip())
    pending = []
    missing = []
    for rel, line_filter in RULES:
        path = root / rel
        if not path.exists():
            missing.append(rel)
            continue
        text = path.read_bytes().decode("utf-8")
        n = count_refs(text, line_filter)
        if n:
            pending.append((rel, n))
            if not check:
                path.write_bytes(retarget_text(text, line_filter).encode("utf-8"))
    if missing:
        print("אזהרה: קבצים שלא נמצאו (אולי שונה שמם ב-upstream, צריך לעדכן את הכללים):")
        for rel in missing:
            print("  ", rel)
    total = sum(n for _, n in pending)
    if check:
        if pending:
            print(f"נמצאו {total} הפניות לזהות אחרת ב-{len(pending)} קבצים של מסלול המוצר:")
            for rel, n in pending:
                print(f"  {n:4d}  {rel}")
            sys.exit(1)
        print(f"מסלול המוצר (פרסום ועדכונים) מכוון ל-{OURS_SLUG}.")
        sys.exit(1 if missing else 0)
    print(f"הוחלפו {total} הפניות ב-{len(pending)} קבצים.")
    for rel, n in pending:
        print(f"  {n:4d}  {rel}")


if __name__ == "__main__":
    main()
