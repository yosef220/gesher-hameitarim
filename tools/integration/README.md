# כלי האינטגרציה

שלושה תפקידים: **ענף המוצר** (`build_product.py` והתור), **הכיוון לריפו שלנו** (`retarget_repository.py`), ו**מרשם ה-PRs**. השיטה כולה מתועדת ב-[`docs/he/07-upstream-sync.md`](../../docs/he/07-upstream-sync.md).

## ענף המוצר

```bash
python3 -I tools/integration/build_product.py --fetch
```

```bash
python3 -I tools/integration/build_product.py --check
```

```bash
python3 -I tools/integration/build_product.py --skip-conflicts
```

הבנייה נעשית ב-worktree זמני ולא נוגעת בעץ העבודה. פריט ש-upstream כבר מיזג מדולג לבד. עם `--skip-conflicts`, גם פריט שמתנגש מדולג ומסומן כממתין. להתנגשות שצריך לפתור: `--topic <מזהה>`, ואחרי הפתרון `--pin <מזהה>`. כשה-CI אישר את `product-candidate`: ‏`--promote`.

## מרשם ה-PRs

הכלים האלה מפיקים את `docs/he/04-pr-register.md`. הם מושכים את כל ה-PRs של upstream, מסמלצים מיזוג של כל אחד מול main ומחלקים לגלים. **הם לא משנים קוד:** הסימולציה רצה עם `git merge-tree`, בלי לגעת בעץ העבודה.

## הרצה מלאה

את הפקודות מריצים משורש הריפו. `DATA` היא תיקייה זמנית לנתונים.

```bash
DATA=/tmp/gesher-integration && mkdir -p "$DATA"
```

```bash
git fetch upstream '+refs/heads/main:refs/remotes/upstream/main' '+refs/pull/*/head:refs/pr/*' '+refs/pull/*/merge:refs/prmerge/*'
```

```bash
git remote add lev https://github.com/Lev-Good/gesher 2>/dev/null; git fetch lev '+refs/heads/*:refs/remotes/lev/*' '+refs/tags/*:refs/tags/lev/*' --no-tags
```

```bash
python3 -I tools/integration/classify_prs.py "$PWD" "$DATA/prs.json"
```

```bash
python3 -I tools/integration/simulate_merges.py "$PWD" "$DATA/prs.json" "$DATA/merge_sim.json"
```

```bash
python3 -I tools/integration/sequential_sim.py "$PWD" "$DATA/merge_sim.json"
```

```bash
git log --format='%s' v0.2.0..upstream/main | grep -oE '\(#[0-9]+\)$|Merge pull request #[0-9]+' | grep -oE '[0-9]+' | sort -n -u > "$DATA/merged_after_020.txt"
```

```bash
cp tools/integration/pr_web_snapshot_2026-11-25.tsv "$DATA/pr_web.tsv"
```

```bash
python3 -I tools/integration/build_pr_register.py "$DATA" docs/he/04-pr-register.md
```

## הקבצים

| קובץ | תפקיד |
|---|---|
| `classify_prs.py` | מסווג כל PR (ממוזג, פתוח או סגור) לפי git, ומאתר את מספרי ה-issues מהפערים ברצף המספרים |
| `simulate_merges.py` | ממזג (בסימולציה) כל PR שלא מוזג מול main, ומדווח: נקי, מתנגש (באילו קבצים) או "כבר ב-main" |
| `sequential_sim.py` | ממזג ברצף את כל ה-PRs הנקיים ומגלה מי מתנגש זה בזה. כותב `waves_seq.json` |
| `combine.py` | מצליב את רשימות האתר עם git ומדווח על אי-התאמות |
| `build_pr_register.py` | בונה את מרשם ה-PRs בעברית, כולל קטגוריות וגלים |
| `build_product.py` | בונה את ענף המוצר מהתור, מדלג על מה ש-upstream מיזג, ומקדם את `product` בלי לדרוס היסטוריה |
| `product-queue.tsv` | התור של ענף המוצר: ה-PRs שעוד לא אושרו ב-upstream, לפי סדר המיזוג, כל אחד עם SHA נעוץ |
| `retarget_repository.py` | מכוון לריפו שלנו את פרסום הגרסאות ואת מקור העדכונים. מריצים אחרי כל סנכרון |
| `pr_web_snapshot_2026-11-25.tsv` | צילום של רשימות ה-PRs הפתוחים והסגורים מהאתר: מצב, מחבר, תוויות וכותרת. את המצב (פתוח או סגור) אי אפשר לקבל מ-git בלבד |

## מגבלות

- מצב ה-PR (פתוח או סגור) נלקח מהצילום ולא מה-API: הסשן שיצר את הכלים לא קיבל גישת API לריפו של upstream. כדי לרענן, צריך לצלם את הרשימות מחדש.
- סימולציה נקייה מראה רק שאין התנגשות טקסטואלית. התאמה סמנטית נבדקת רק ב-CI ובבדיקות.
