"""ממזג ברצף (בסימולציה) את כל ה-PRs הנקיים, ומגלה אילו מהם מתנגשים זה בזה.

שימוש: python3 -I sequential_sim.py <נתיב-ריפו> <merge_sim.json>
כותב waves_seq.json ליד merge_sim.json.
"""
import os
import subprocess, json, sys
repo, sim_json = sys.argv[1], sys.argv[2]
def git(*a, inp=None):
    r = subprocess.run(["git","-C",repo,*a],capture_output=True,text=True,input=inp)
    return r.returncode, r.stdout.strip(), r.stderr.strip()
sim = json.load(open(sim_json))
for x in sim:
    if x["verdict"]=="error":
        ref = "refs/remotes/lev/fix/app-compat" if x["name"].startswith("lev") else "refs/pr/"+x["name"][1:]
        c,o,e = git("merge-tree","--write-tree","--name-only","--no-messages","origin/main",ref)
        print("שגיאה", x["name"], x["head_subject"][:70], "|", (e or o)[:200])
clean = [x for x in sim if x["verdict"]=="clean"]
clean.sort(key=lambda x: int(x["name"][1:]))
_, acc, _ = git("rev-parse","origin/main")
ok, fail = [], []
for x in clean:
    ref = "refs/pr/"+x["name"][1:]
    c, o, e = git("merge-tree","--write-tree","--name-only","--no-messages",acc,ref)
    lines = o.splitlines()
    if c == 0:
        _, pr_sha, _ = git("rev-parse", ref)
        _, new, _ = git("commit-tree", lines[0], "-p", acc, "-p", pr_sha, "-m", f"sim merge {x['name']}")
        acc = new; ok.append(x["name"])
    else:
        fail.append((x["name"], lines[1:6]))
print(f"\nמיזוג רציף של ה-PRs הנקיים: {len(ok)} נכנסו ברצף, {len(fail)} התנגשו עם PRs אחרים")
for n, f in fail: print("  ", n, f)
print("ראש הסימולציה:", acc)
out = os.path.join(os.path.dirname(os.path.abspath(sim_json)), "waves_seq.json")
json.dump({"ok": ok, "fail": [n for n, _ in fail]}, open(out, "w"))
print("נכתב:", out)
