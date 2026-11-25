"""מסווג את כל ה-PRs של upstream לפי git: ממוזג, פתוח (יש ענף merge) או סגור.

שימוש: python3 -I classify_prs.py <נתיב-ריפו> <קובץ-פלט.json>
"""
import subprocess, re, json, sys, os
repo = sys.argv[1]; out = sys.argv[2]
def git(*a):
    return subprocess.run(["git","-C",repo,*a],capture_output=True,text=True).stdout
heads = {}
for line in git("for-each-ref","refs/pr","--format=%(refname) %(objectname)").splitlines():
    ref, sha = line.split(); heads[int(ref.rsplit("/",1)[1])] = sha
merges = set(int(l.rsplit("/",1)[1]) for l in git("for-each-ref","refs/prmerge","--format=%(refname)").splitlines())
# קומיטים ב-main שמזכירים (#N): מיזוג squash או merge
main_log = git("log","upstream/main","--format=%H%x09%s")
squash = {}
for line in main_log.splitlines():
    h, s = line.split("\t",1)
    for m in re.finditer(r"\(#(\d+)\)", s): squash.setdefault(int(m.group(1)), (h, s))
    m = re.match(r"Merge pull request #(\d+)", s)
    if m: squash.setdefault(int(m.group(1)), (h, s))
# אילו ראשי PR נגישים מ-main
reach = set(git("rev-list","upstream/main").split())
lev = set(git("rev-list","lev/main","lev/v0.2.0-lev1").split())
rows = []
for n in sorted(heads):
    sha = heads[n]
    st = "merged" if (n in squash or sha in reach) else ("open" if n in merges else "closed-unmerged")
    subj = git("log","-1","--format=%s",sha).strip()
    date = git("log","-1","--format=%cs",sha).strip()
    author = git("log","-1","--format=%an",sha).strip()
    mb = git("merge-base",sha,"upstream/main").strip()
    ahead = int(git("rev-list","--count",f"{mb}..{sha}").strip() or 0) if mb else -1
    stat = git("diff","--shortstat",mb,sha).strip() if mb else ""
    files = int(re.search(r"(\d+) files? changed", stat).group(1)) if "changed" in stat else 0
    rows.append(dict(n=n, state=st, head=sha[:9], head_subject=subj, date=date, author=author,
                     main_title=squash.get(n,(None,None))[1], ahead=ahead, files=files, stat=stat))
json.dump(rows, open(out,"w"), ensure_ascii=False, indent=1)
from collections import Counter
c = Counter(r["state"] for r in rows)
print("סה\"כ PRs:", len(rows), dict(c))
mx = max(heads); allnums = set(range(1, mx+1)); gaps = sorted(allnums - set(heads))
print("המספר הגבוה ביותר:", mx, "| מספרים בלי PR (issues או נמחקו):", len(gaps))
print("מספרים שהם כנראה issues:", gaps)
