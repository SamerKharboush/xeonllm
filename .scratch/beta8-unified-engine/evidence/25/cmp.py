import json, sys, os
# usage: cmp.py <label> <model-stem> <cell>
BASE = '/Users/sam/firellama/.scratch/beta8-unified-engine/evidence'
REF = {
    'Qwen3-0.6B-Q8_0': (f'{BASE}/gates-beta7/out2/set/Qwen3-0.6B-Q8_0/Qwen3-0.6B-Q8_0-ngl0.answers.json',
                        f'{BASE}/gates-beta8/out/set/Qwen3-0.6B-Q8_0/Qwen3-0.6B-Q8_0-ngl0.answers.json'),
    'Qwen3-8B-Q4_K_M': (f'{BASE}/gates-beta7/out2/set/Qwen3-8B-Q4_K_M/Qwen3-8B-Q4_K_M-ngl0.answers.json',
                        f'{BASE}/gates-beta8/out/set/Qwen3-8B-Q4_K_M/Qwen3-8B-Q4_K_M-ngl0.answers.json'),
}
label, stem, cell = sys.argv[1], sys.argv[2], sys.argv[3]
got = json.load(open(f'{BASE}/25/{label}/{stem}-ngl0.answers.json')).get(cell)
out = {'label': label, 'cell': cell, 'got_len': len(got) if got is not None else None}
for name, p in zip(('beta7_ref', 'beta8_ref'), REF[stem]):
    if not os.path.exists(p):
        out[name] = 'MISSING ' + p; continue
    r = json.load(open(p)).get(cell)
    if got == r:
        out[name] = 'IDENTICAL (len %d)' % len(r); continue
    i = next((j for j in range(min(len(got), len(r))) if got[j] != r[j]), min(len(got), len(r)))
    out[name] = {'diff_offset': i, 'ref_len': len(r), 'got': repr(got[max(0, i - 50):i + 70]), 'ref': repr(r[max(0, i - 50):i + 70])}
print(json.dumps(out, indent=1, ensure_ascii=False))