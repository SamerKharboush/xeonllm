import json, os, sys

E = "/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/26"
G = "/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8"
B7 = "/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta7/out2/set"
S = "ornith-1.0-35b-Q6_K"

refs = {
    "beta8-tensor": f"{G}/out/set/{S}/{S}-tensor.answers.json",
    "beta8-draft": f"{G}/out/set/{S}/{S}-draft.answers.json",
    "beta7-draft": f"{B7}/{S}/{S}-draft.answers.json",
}
labels = ["d1", "d2", "t1", "b7d", "moe", "nopo", "ub512"]
CELLS = ["band16", "band300", "band1100"]


def load(p):
    if not os.path.exists(p):
        return None
    with open(p) as f:
        return json.load(f)


def firstdiff(a, b):
    n = min(len(a), len(b))
    i = next((k for k in range(n) if a[k] != b[k]), None)
    return i if i is not None else n


ref = {k: load(v) for k, v in refs.items()}
out = []
for k, v in refs.items():
    out.append(f"reference {k}: {'loaded' if ref[k] else 'MISSING'} {v}")
    if ref[k]:
        out.append(f"  cells: {sorted(ref[k].keys())}")

out.append("")
hdr = f"{'label':7s} " + " ".join(f"{c:>10s}" for c in CELLS) + "   vs"
out.append(hdr)
for lab in labels:
    mine = load(f"{E}/{lab}/{S}-" + ("tensor" if lab == "t1" else "draft") + ".answers.json")
    if mine is None:
        out.append(f"{lab:7s} MISSING {E}/{lab}")
        continue
    cells = []
    for c in CELLS:
        a = mine.get(c)
        cells.append("MISSING" if a is None else f"{len(a):>10d}")
    out.append(f"{lab:7s} " + " ".join(cells))
    for rk, rv in ref.items():
        if rv is None:
            continue
        marks = []
        for c in CELLS:
            a, b = mine.get(c), rv.get(c)
            if a is None or b is None:
                marks.append(f"{c}=missing")
                continue
            if a == b:
                marks.append(f"{c}=IDENTICAL")
            else:
                i = firstdiff(a, b)
                marks.append(f"{c}=DIFF@{i}(len {len(a)}/{len(b)})")
        out.append(f"        vs {rk}: " + "; ".join(marks))

out.append("")
out.append("== band1100 first 40 chars ==")
for lab in labels:
    p = f"{E}/{lab}/{S}-" + ("tensor" if lab == "t1" else "draft") + ".answers.json"
    d = load(p)
    if not d or "band1100" not in d:
        out.append(f"{lab:7s} MISSING")
        continue
    out.append(f"{lab:7s} {d['band1100'][:40]!r}")
for rk, rv in ref.items():
    if rv and "band1100" in rv:
        out.append(f"{rk:12s} {rv['band1100'][:40]!r}")

with open(f"{E}/compare.txt", "w") as f:
    f.write("\n".join(out) + "\n")
print("\n".join(out))