import sys, subprocess, tempfile, os
# compares .text of one Mach-O object across two builds, symbol by symbol (sizes from otool)
def syms(path):
    out = subprocess.run(['nm', '-ap', '--defined-only', path], capture_output=True, text=True).stderr + subprocess.run(['nm', '-ap', '--defined-only', path], capture_output=True, text=True).stdout
    addrs = {}
    for l in out.splitlines():
        p = l.split()
        if len(p) == 3 and p[1] in ('t', 'T', 's', 'S'):
            addrs[p[2]] = int(p[0], 16)
    out = subprocess.run(['otool', '-tV', path], capture_output=True, text=True).stdout
    # otool prints the address then the symbol header line "symbol_name:" inside the disassembly
    size = {}
    cur = None
    for l in out.splitlines():
        s = l.strip()
        if s.endswith(':') and ' ' not in s and s[:-1] in addrs:
            cur = s[:-1]; size[cur] = [None, None]
        elif cur:
            m = l.split()
            if m and all(c in '0123456789abcdef' for c in m[0]) and len(m[0]) == 16:
                a = int(m[0], 16)
                if size[cur][0] is None: size[cur][0] = a
                size[cur][1] = a
    def text(sym):
        # extract bytes of one function from otool -tV by address range
        lo, hi = size[sym]
        out = subprocess.run(['otool', '-tV', path], capture_output=True, text=True).stdout
        ins = []
        on = False
        for l in out.splitlines():
            m = l.split('\t')
            if m and all(c in '0123456789abcdef' for c in m[0]) and len(m[0]) == 16:
                a = int(m[0], 16)
                if a == lo: on = True
                if a >= hi: on = False
                if on and len(m) > 2:
                    ins.append(tuple(m[1:3]))
        return tuple(x for x in ins if x[0] != '...')
    return addrs, {k: text(k) for k in addrs if k in size and size[k][0] is not None}
a, b = sys.argv[1], sys.argv[2]
aa, ta = syms(a); ab, tb = syms(b)
common = [k for k in ta if k in tb]
diff = [k for k in common if ta[k] != tb[k]]
print(f"{a}: {len(ta)} sized syms vs {b}: {len(tb)}; {len(diff)}/{len(common)} differ; only-a {len(set(ta)-set(tb))} only-b {len(set(tb)-set(ta))}")
for k in sorted(diff):
    n = sum(1 for x, y in zip(ta[k], tb[k]) if x != y)
    print(f"  {k}: {len(ta[k])} vs {len(tb[k])} instrs, {n} differ")