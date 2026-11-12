#!/usr/bin/env python3
# Parse the llama-bench CSVs in this directory into the comparison tables.
import csv
import glob
import os
import re
import statistics

E = os.path.dirname(os.path.abspath(__file__))
FILES = sorted(glob.glob(os.path.join(E, "bench-*.csv")))

rows = {}
for path in FILES:
    base = os.path.basename(path)[:-4]
    m = re.match(r"bench-(.+)-ub(\d+)-(new|old)-p(\d+)", base)
    if not m:
        continue
    tag, ub, side, rep = m.group(1), m.group(2), m.group(3), m.group(4)
    with open(path, newline="") as fh:
        rdr = csv.DictReader(fh)
        for row in rdr:
            key = (tag, ub, row["n_prompt"], row["n_gen"], row["n_depth"])
            rows.setdefault(key, {}).setdefault((side, rep), []).append(
                (float(row["avg_ts"]), float(row["stddev_ts"]))
            )

order = sorted({(t, u) for (t, u, _, _, _) in rows})
for tag, ub in order:
    print(f"### {tag} ub={ub}")
    print("| test | depth | new p1 | new p2 | old p1 | old p2 | verdict |")
    print("|---|---|---|---|---|---|---|")
    keys = sorted(k for k in rows if k[0] == tag and k[1] == ub)
    for key in keys:
        _, _, np_, ng_, depth = key
        test = f"pp{np_}" if int(np_) > 0 else f"tg{ng_}"
        vals = {}
        for side in ("new", "old"):
            for rep in ("1", "2"):
                v = rows[key].get((side, rep))
                vals[(side, rep)] = v[0] if v else None
        cells = []
        for side in ("new", "old"):
            for rep in ("1", "2"):
                v = vals[(side, rep)]
                cells.append("-" if v is None else f"{v[0]:.6f} +- {v[1]:.6f}")
        new = [vals[("new", "1")], vals[("new", "2")]]
        old = [vals[("old", "1")], vals[("old", "2")]]
        if all(v is not None for v in new + old):
            newmin = min(v[0] for v in new)
            newmax = max(v[0] for v in new)
            oldmin = min(v[0] for v in old)
            oldmax = max(v[0] for v in old)
            if newmin > oldmax:
                verdict = "new higher"
            elif oldmin > newmax:
                verdict = "old higher"
            else:
                verdict = "not resolved"
        else:
            verdict = "not resolved"
        print(f"| {test} | {depth} | " + " | ".join(cells) + f" | {verdict} |")
    print()
