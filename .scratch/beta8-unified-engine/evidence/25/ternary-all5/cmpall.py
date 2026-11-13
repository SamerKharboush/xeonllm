import json, os, sys
BASE = '/Users/sam/firellama/.scratch/beta8-unified-engine/evidence'
STEM = 'Ternary-Bonsai-2-27B-PQ2_0'
REF = {
    'b7': f'{BASE}/gates-beta7/out2/set/{STEM}/{STEM}-ngl0.answers.json',
    'b8': f'{BASE}/gates-beta8/out/set/{STEM}/{STEM}-ngl0.answers.json',
}
CELLS = ('band16', 'band300', 'band1100')
ref = {k: json.load(open(p)) if os.path.exists(p) else None for k, p in REF.items()}

label = sys.argv[1]
path = sys.argv[2] if len(sys.argv) > 2 else f'{BASE}/25/ternary-all5/{label}/{STEM}-ngl0.answers.json'
got = json.load(open(path)) if os.path.exists(path) else {}

lines = []
for cell in CELLS:
    g = got.get(cell)
    parts = []
    for name in ('b7', 'b8'):
        r = ref[name].get(cell) if ref[name] else None
        if r is None:
            parts.append(f'{name}: MISSING'); continue
        if g == r:
            parts.append(f'{name}: IDENTICAL'); continue
        i = next((j for j in range(min(len(g), len(r))) if g[j] != r[j]), min(len(g), len(r)))
        parts.append(f'{name}: diff@{i} (len {len(g)} vs {len(r)})')
    lines.append(f'{label}\t{cell}\tlen={len(g) if g is not None else None}\t' + '\t'.join(parts))
print('\n'.join(lines))
open(f'{BASE}/25/ternary-all5/compare.txt', 'a').write('\n'.join(lines) + '\n')