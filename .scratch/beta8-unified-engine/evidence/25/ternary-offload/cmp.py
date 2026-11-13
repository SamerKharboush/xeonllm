import json, os
BASE = '/Users/sam/firellama/.scratch/beta8-unified-engine/evidence'
STEM = 'Ternary-Bonsai-2-27B-PQ2_0'
E = f'{BASE}/25/ternary-offload'
REF = {
    'b7': f'{BASE}/gates-beta7/out2/set/{STEM}/{STEM}-ngl0.answers.json',
    'b8': f'{BASE}/gates-beta8/out/set/{STEM}/{STEM}-ngl0.answers.json',
}
CELLS = ('band16', 'band300', 'band1100')
ref = {k: json.load(open(p)) for k, p in REF.items()}
RUNS = [
    ('nopo', f'{E}/nopo/{STEM}-ngl0nopo.answers.json'),
    ('nopo2', f'{E}/nopo2/{STEM}-ngl0nopo.answers.json'),
    ('mb', f'{E}/mb/{STEM}-ngl0.answers.json'),
    ('base', f'{E}/base/{STEM}-ngl0.answers.json'),
]
out = []
for label, path in RUNS:
    got = json.load(open(path))
    for cell in CELLS:
        g = got.get(cell)
        parts = []
        for name in ('b7', 'b8'):
            r = ref[name].get(cell)
            if g == r:
                parts.append(f'{name}: IDENTICAL')
            else:
                i = next((j for j in range(min(len(g), len(r))) if g[j] != r[j]), min(len(g), len(r)))
                parts.append(f'{name}: diff@{i} (len {len(g)} vs {len(r)})')
        out.append(f'{label}\t{cell}\tlen={len(g)}\t' + '\t'.join(parts))
# also nopo vs mb vs base
for a, b in (('nopo', 'mb'), ('mb', 'base')):
    ga = json.load(open(dict(RUNS)[a])); gb = json.load(open(dict(RUNS)[b]))
    for cell in CELLS:
        out.append(f'{a}-vs-{b}\t{cell}\t' + ('IDENTICAL' if ga[cell] == gb[cell] else 'DIFFERS'))
text = '\n'.join(out) + '\n'
open(f'{E}/compare.txt', 'w').write(text)
print(text)