#!/usr/bin/env python3
"""Parse test-backend-ops perf console output into rows: shape -> us/run, GB/s, pipeline base."""
import re
import sys

CASE_RE = re.compile(
    r"MUL_MAT\(type_a=(?P<ta>[^,]+),type_b=(?P<tb>[^,]+),m=(?P<m>\d+),n=(?P<n>\d+),"
    r"k=(?P<k>\d+),bs=\[(?P<bs0>\d+),(?P<bs1>\d+)\],nr=\[(?P<nr0>\d+),(?P<nr1>\d+)\]"
)
PIPE_RE = re.compile(r"compiling pipeline: base = '(?P<base>[^']+)'")
LOAD_RE = re.compile(r"loaded (?P<base>\S+)")
RESULT_RE = re.compile(r"(?P<runs>\d+)\s+runs\s+-\s+(?P<us>[\d.]+)\s+us/run\s+-\s+(?P<kb>[\d.]+)\s+kB/run\s+-\s+(?P<gb>[\d.]+)\s+GB/s")


def main(paths):
    rows = []
    for path in paths:
        cur_base = None
        with open(path, errors="replace") as f:
            for line in f:
                m = PIPE_RE.search(line)
                if m:
                    cur_base = m.group("base")
                    continue
                m = LOAD_RE.search(line)
                if m:
                    cur_base = m.group("base")
                    continue
                if "MUL_MAT(" not in line:
                    continue
                cm = CASE_RE.search(line)
                rm = RESULT_RE.search(line.replace("\x1b[1;34m", "").replace("\x1b[0m", ""))
                if not cm or not rm:
                    continue
                rows.append(dict(
                    type_a=cm.group("ta"),
                    m=int(cm.group("m")),
                    n=int(cm.group("n")),
                    k=int(cm.group("k")),
                    bs=int(cm.group("bs0")),
                    runs=int(rm.group("runs")),
                    us=float(rm.group("us")),
                    kb=float(rm.group("kb")),
                    gb=float(rm.group("gb")),
                    pipeline=cur_base,
                    src=path,
                ))
    hdr = f"{'type_a':8s} {'m':>7s} {'n':>3s} {'k':>7s} {'bs':>3s} {'runs':>6s} {'us/run':>10s} {'GB/s':>8s}  pipeline"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print(f"{r['type_a']:8s} {r['m']:7d} {r['n']:3d} {r['k']:7d} {r['bs']:3d} {r['runs']:6d} "
              f"{r['us']:10.2f} {r['gb']:8.2f}  {r['pipeline']}")
    print(f"\n{len(rows)} MUL_MAT perf cases parsed")


if __name__ == "__main__":
    main(sys.argv[1:])
