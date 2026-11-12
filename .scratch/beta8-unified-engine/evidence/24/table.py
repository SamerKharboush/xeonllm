#!/usr/bin/env python3
import glob, os, re, sys
d = sys.argv[1]
print(f"{'label':4} {'status':7} {'secs':7} {'prompt':22} {'prompt_ms_tok':13} {'eval_ms_tok':11} {'text':8} {'mismatch':8} {'timeouts':8}")
for f in sorted(glob.glob(os.path.join(d, 'repro-*.out'))):
    label = re.search(r'repro-(.*)\.out', f).group(1)
    out = open(f).read()
    lines = [l for l in out.splitlines() if l.strip()]
    first = lines[0] if lines else ''
    p = first.split()
    status = p[0] if p else '?'
    secs = p[1] if len(p) > 1 else '?'
    txt = lines[-1][:40] if lines else ''
    log = os.path.join(d, 'repro-%s.log' % label)
    pp = ev = mm = to = '?'
    if os.path.exists(log):
        s = open(log, errors='replace').read()
        m = re.findall(r'prompt eval time =.*?([\d.]+) tokens per second', s)
        pp = (m[-1] + ' tok/s') if m else '-'
        m = re.findall(r'\n[^\n]*eval time =[^\n]*\(\s*([\d.]+) ms per token', s)
        ev = (m[-1] + ' ms/tok') if m else '-'
        mm = str(s.count('does not match'))
        to = str(s.count('Timeout'))
    print(f"{label:4} {status:7} {secs:7} {pp:10} {ev:11} {txt:8} {mm:8} {to:8}")