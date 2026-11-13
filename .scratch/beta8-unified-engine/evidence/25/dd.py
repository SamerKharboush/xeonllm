import subprocess, sys, re
# usage: 2-dis.txt <objdir-suffix-less path A> <path B> <symbol> [max lines]
# prints side-by-side differing instruction lines for one function
def syms(p):
    o = subprocess.run(['nm', '-ap', '--defined-only', p], capture_output=True, text=True).stdout
    return {l.split()[2]: int(l.split()[0], 16) for l in o.splitlines() if len(l.split()) == 3 and l.split()[1] in 'tT'}
def dis(p, lo):
    o = subprocess.run(['otool', '-tvV', p], capture_output=True, text=True).stdout.splitlines()
    r = {}; on = False
    for l in o:
        if l and not l.startswith('\t') and l.endswith(':'):
            on = True; continue
        s = l.split('\t')
        if s and re.fullmatch('[0-9a-f]{16}', s[0]):
            a = int(s[0], 16)
            if on: r[a] = '\t'.join(x for x in s[1:] if x not in ('...', ''))
    return r
def norm(t):
    t = re.sub(r'## literal pool for: .*', '', t)
    t = re.sub(r'0x[0-9a-f]+\(%rip\)', 'RIP', t)
    return t
A, B, name = sys.argv[1], sys.argv[2], sys.argv[3]
lim = int(sys.argv[4]) if len(sys.argv) > 4 else 10
da, db = syms(A)[name], syms(B)[name]
xa, xb = dis(A, da), dis(B, db)
# split into functions: next symbol address after lo
fa = sorted(a for a in xa if a >= da)
hi = next((a for a in fa if a > da), 1 << 40)
n = 0
for a in sorted(xa):
    if a >= hi: break
    if norm(xa[a]) != norm(xb.get(a, '')):
        print(f'{a:x}  fa   {xa[a]}')
        print(f'{a:x}  stat {xb.get(a)}')
        n += 1
        if n >= lim: break
print(f'{name}: {n}+ differing lines shown')