import json, os, sys
BASE = '/Users/sam/firellama/.scratch/beta8-unified-engine/evidence'
E = f'{BASE}/25/ternary'
STEM = 'Ternary-Bonsai-2-27B-PQ2_0'
b7 = json.load(open(f'{BASE}/gates-beta7/out2/set/{STEM}/{STEM}-ngl0.answers.json'))
b8 = json.load(open(f'{BASE}/gates-beta8/out/set/{STEM}/{STEM}-ngl0.answers.json'))
labels = sys.argv[1:] or ['b7']
rows = []
for L in labels:
    p = f'{E}/{L}/{STEM}-ngl0.answers.json'
    if not os.path.exists(p):
        print(L, 'MISSING'); continue
    got = json.load(open(p))
    for cell in ('band16', 'band300', 'band1100'):
        g = got.get(cell)
        out = {'label': L, 'cell': cell, 'len': len(g) if g is not None else None}
        for name, ref in (('beta7', b7.get(cell)), ('beta8', b8.get(cell))):
            if g == ref:
                out['vs_' + name] = 'IDENTICAL'
            elif g is None or ref is None:
                out['vs_' + name] = 'MISSING'
            else:
                i = next((j for j in range(min(len(g), len(ref))) if g[j] != ref[j]), min(len(g), len(ref)))
                out['vs_' + name] = f'diff@{i} (len {len(g)} vs {len(ref)})'
        rows.append(out)
for r in rows:
    print(f"{r['label']:10s} {r['cell']:9s} len={r['len']}  vs beta.7: {r['vs_beta7']:28s} vs beta8: {r['vs_beta8']}")