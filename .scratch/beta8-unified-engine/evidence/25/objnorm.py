import subprocess, sys, re
FA = '/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/'
ST = '/Users/sam/firellama/vendor/llama.cpp/build-static/ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/'
def syms(p):
    o = subprocess.run(['nm', '-ap', '--defined-only', p], capture_output=True, text=True).stdout
    return {l.split()[2]: int(l.split()[0], 16) for l in o.splitlines() if len(l.split()) == 3 and l.split()[1] in 'tT'}
def dis(p):
    o = subprocess.run(['otool', '-tvV', p], capture_output=True, text=True).stdout.splitlines()
    r = {}; on = False
    for l in o:
        if l and not l.startswith('\t') and l.endswith(':'):
            on = True; continue
        s = l.split('\t')
        if s and re.fullmatch('[0-9a-f]{16}', s[0]):
            if on: r[int(s[0], 16)] = '\t'.join(x for x in s[1:] if x not in ('...', ''))
    return r
def norm(t):
    t = re.sub(r'## literal pool for: .*', '', t)
    t = re.sub(r'0x[0-9a-f]+\(%rip\)', 'RIP', t)
    return re.sub(r'\s+', ' ', t).strip()
for o in sys.argv[1:]:
    sa, sb = syms(FA + o), syms(ST + o)
    xa, xb = dis(FA + o), dis(ST + o)
    addrs = sorted(xa)
    bad = []
    for i, a in enumerate(addrs):
        hi = addrs[i + 1] if i + 1 < len(addrs) and addrs[i + 1] - a < 0x4000 else a + 0x1000
        for k in range(a, min(hi, a + 0x10000)):
            pass
        # only compare within this function's address span up to next insn
        ks = [k for k in addrs if a <= k < hi]
        d = [k for k in ks if norm(xa[k]) != norm(xb.get(k, ''))]
        if d:
            name = [n for n, v in sb.items() if v == a]
            bad.append((a, name[:1], d[:4]))
    print(o, f'{len(bad)} differing functions (normalized)')
    for a, n, d in bad[:6]:
        print(f'  {a:x} {n}')
        for k in d[:3]:
            print(f'    fa   {xa[k]}')
            print(f'    stat {xb.get(k)}')