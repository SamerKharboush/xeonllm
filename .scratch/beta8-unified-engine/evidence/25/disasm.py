import subprocess, sys
# demangled otool -tV of a function range, for eyeball diffing
p, lo, hi = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
out = subprocess.run(['otool', '-tvV', p], capture_output=True, text=True).stdout.splitlines()
on = False
for l in out:
    s = l.split('\t')
    if s and len(s[0]) == 16 and all(c in '0123456789abcdef' for c in s[0]):
        a = int(s[0], 16)
        if a == lo: on = True
        if a >= hi: on = False
        if on: print(l)
    elif on and l and not l.startswith('\t'):
        print('   ', l)