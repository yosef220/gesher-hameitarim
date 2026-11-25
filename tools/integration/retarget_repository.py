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
OURS_SLUG = "yosef220/APK"   # האותיות הקנוניות, כפי ש-GitHub מחזיר (חשוב להשוואות רגישות לאותיות)
OURS_ID = "1471037894"

ID_PATTERN = re.compile(r"(?<![0-9])" + UPSTREAM_ID + r"(?![0-9])")

# כל כלל: נתיב, ואם יש — ביטוי רגולרי שמגביל את ההחלפה לשורות שתואמות לו
RULES = [
    ("tools/ci/release_version.py", None),
    (".github/workflows/publish-release.yml", None),
    # רק שלב אימות התג (שחרור גרסה), לא שורות הראיות של TCP שרצות במצב פורק
    (".github/workflows/ci.yml", re.compile(r"github\.event_name == 'push' && github\.ref_type == 'tag'")),
    ("tools/package/gesher-update.ps1", None),
    ("tests/windows/shell/UpdateChecks.ps1", None),
    ("tests/windows/shell/UpdateTransportChecks.ps1", None),
    ("tests/windows/shell/ControlPanelUpdateChecks.ps1", None),
    ("tests/windows/shell/PortableProfileChecks.ps1", None),
    (".github/pull_request_template.md", None),
    # הבדיקה שנועצת את תנאי אימות התג (מסלול השחרור). שורת ניתוב ה-runner של automerge לא משתנה
    (".github/scripts/test_automerge_workflows.py", re.compile(r"self\.assertEqual\(identity\['if'\]")),
]


def retarget_text(text, line_filter):
    def sub(s):
        return ID_PATTERN.sub(OURS_ID, s.replace(UPSTREAM_SLUG, OURS_SLUG))
    if line_filter is None:
        return sub(text)
    lines = text.splitlines(keepends=True)
    return "".join(sub(l) if line_filter.search(l) else l for l in lines)


def count_refs(text, line_filter):
    lines = text.splitlines() if line_filter is not None else [text]
    return sum(l.count(UPSTREAM_SLUG) + len(ID_PATTERN.findall(l))
               for l in lines if line_filter is None or line_filter.search(l))


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
            print(f"נמצאו {total} הפניות ל-upstream ב-{len(pending)} קבצים של מסלול המוצר:")
            for rel, n in pending:
                print(f"  {n:4d}  {rel}")
            sys.exit(1)
        print("מסלול המוצר (פרסום ועדכונים) מכוון לריפו שלנו.")
        sys.exit(1 if missing else 0)
    print(f"הוחלפו {total} הפניות ב-{len(pending)} קבצים.")
    for rel, n in pending:
        print(f"  {n:4d}  {rel}")


if __name__ == "__main__":
    main()
