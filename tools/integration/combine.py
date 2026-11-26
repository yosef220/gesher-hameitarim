"""מצליב את צילום רשימות ה-PRs מהאתר עם הסיווג של git ועם תוצאות הסימולציה.

שימוש: python3 -I combine.py <תיקיית-נתונים>
"""
import json, sys, csv
sp = sys.argv[1]
web = {}
for line in open(f"{sp}/pr_web.tsv", encoding="utf-8"):
    n, st, au, lab, title = line.rstrip("\n").split("\t", 4)
    web[int(n)] = dict(state=st, author=au, labels=lab, title=title)
sim = {int(x["name"][1:]): x for x in json.load(open(f"{sp}/merge_sim.json")) if x["name"].startswith("#")}
prs = {r["n"]: r for r in json.load(open(f"{sp}/prs.json"))}
missing_in_git = sorted(set(web) - set(prs)); merged_in_git_but_web_unmerged = sorted(n for n in web if prs.get(n,{}).get("state")=="merged")
print("ב-web ולא ב-git:", missing_in_git, "| מסומנים ממוזגים ב-git אך לא ב-web:", merged_in_git_but_web_unmerged)
not_in_web = sorted(n for n, r in prs.items() if r["state"] != "merged" and n not in web)
print("לא ממוזגים ב-git ולא ברשימות web:", not_in_web)
rows = []
for n in sorted(web, reverse=True):
    s = sim.get(n, {}); p = prs.get(n, {})
    rows.append(dict(n=n, **web[n], verdict=s.get("verdict","?"), n_conflicts=s.get("n_conflicts",0),
                     conflicts=s.get("conflicts",[]), files=p.get("files"), ahead=p.get("ahead"), date=p.get("date")))
json.dump(rows, open(f"{sp}/unmerged_combined.json","w"), ensure_ascii=False, indent=1)
from collections import Counter
print(Counter((r["state"], r["verdict"]) for r in rows))
