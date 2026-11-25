"""מסמלץ מיזוג של כל PR שלא מוזג (ושל ענף Lev-Good) מול main, בעזרת git merge-tree.

שימוש: python3 -I simulate_merges.py <נתיב-ריפו> <prs.json> <קובץ-פלט.json>
"""
import subprocess, json, sys
repo, prs_json, out = sys.argv[1], sys.argv[2], sys.argv[3]
def git(*a, check=False):
    r = subprocess.run(["git","-C",repo,*a],capture_output=True,text=True)
    return r.returncode, r.stdout
_, main_tree = git("rev-parse","origin/main^{tree}"); main_tree = main_tree.strip()
rows = json.load(open(prs_json))
targets = [(f"#{r['n']}", f"refs/pr/{r['n']}", r) for r in rows if r["state"] != "merged"]
targets.append(("lev/fix/app-compat", "refs/remotes/lev/fix/app-compat", None))
res = []
for name, ref, r in targets:
    code, outp = git("merge-tree","--write-tree","--name-only","--no-messages","origin/main",ref)
    lines = outp.strip().splitlines()
    tree = lines[0] if lines else ""
    conflicts = [l for l in lines[1:] if l.strip()]
    if code == 0:
        verdict = "already-in-main" if tree == main_tree else "clean"
    elif code == 1:
        verdict = "conflict"
    else:
        verdict = "error"
    # כמה ה-PR היה מוסיף מעל main (רק במיזוג נקי)
    added = ""
    if verdict == "clean":
        _, added = git("diff","--shortstat",main_tree,tree); added = added.strip()
    res.append(dict(name=name, state=(r or {}).get("state","fork"), verdict=verdict,
                    conflicts=conflicts, n_conflicts=len(conflicts), would_add=added,
                    head_subject=(r or {}).get("head_subject",""), files=(r or {}).get("files"),
                    ahead=(r or {}).get("ahead"), date=(r or {}).get("date")))
json.dump(res, open(out,"w"), ensure_ascii=False, indent=1)
from collections import Counter
for st in ("open","closed-unmerged","fork"):
    c = Counter(x["verdict"] for x in res if x["state"]==st)
    print(st, dict(c))
cf = Counter(f for x in res for f in x["conflicts"])
print("\nקבצים עם הכי הרבה התנגשויות:")
for f, k in cf.most_common(25): print(f"{k:4d}  {f}")
