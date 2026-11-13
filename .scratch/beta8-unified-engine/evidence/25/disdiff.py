import subprocess, re, sys
# prints the instruction lines that differ between two Mach-O objects' disassembly
FA = '/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/'
ST = '/Users/sam/firellama/vendor/llama.cpp/build-static/ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/'
def dis(p):
    out = subprocess.run(['otool', '-tvV', p], capture_output=True, text=True).stdout.splitlines()
    d = {}
    on = False
    for l in out:
        if l and not l.startswith('\t') and l.endswith(':'):
            on = True; continue
        if on:
            m = l.split('\t')
            if m and re.fullmatch('[0-9a-f]{16}', m[0]):
                d[int(m[0], 16)] = '\t'.join(x for x in m[1:] if x not in ('...', ''))
    return d
for o in sys.argv[1:]:
    a, b = dis(FA + o), dis(ST + o)
    shown = 0
    print('==', o)
    for k in sorted(set(a) & set(b)):
        if a[k] != b[k]:
            print(f'  {k:x}: fa    {a[k]}')
            print(f'  {k:x}: stat  {b[k]}')
            shown += 1
            if shown >= 8: break