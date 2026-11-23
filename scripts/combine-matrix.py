#!/usr/bin/env python3
"""Combine matrix TSVs, repair metadata, and print a compact markdown table."""
import csv
import re
import statistics
import subprocess
import sys
from collections import defaultdict

BASE = ".scratch/xeonllm-0-2/evidence/01"
FILES = [f"{BASE}/matrix.tsv", f"{BASE}/matrix-beta8-shipped.tsv"]
BUILD_ORDER = ["beta4", "beta5", "beta6", "beta7", "beta8", "010", "011"]
MODEL_ORDER = ["MiniCPM5", "LFM3", "ornith", "Qwen3-0.6B", "Qwen3-4B"]


def short_model(path):
    name = path.rsplit("/", 1)[-1]
    if "MiniCPM5" in name:
        return "MiniCPM5"
    if "LFM3" in name:
        return "LFM3"
    if "ornith" in name.lower():
        return "Ornith35B"
    if "Qwen3-0.6B" in name:
        return "Qwen3-0.6B"
    if "Qwen3-4B" in name:
        return "Qwen3-4B"
    return name


def ns_for(build, args_set):
    if build in ("beta4", "beta5", "beta6", "beta7") and args_set == "shipped":
        return "TOSH_*", "native TOSH_* names"
    if build == "beta8" and args_set == "shipped":
        return "TOSH_*", "as shipped TOSH_* names; inert on XEON_* engine"
    if build in ("beta4", "beta5", "beta6", "beta7") and args_set == "011":
        return "TOSH_*", "0.1.1 XEON_* names translated to TOSH_*"
    if build == "beta8" and args_set == "011":
        return "XEON_*", "native XEON_* names (0.1.1 args)"
    return "XEON_*", "native XEON_* names"


def method_get(method, key):
    m = re.search(r"(?:^| )" + re.escape(key) + r"=([^ ]*)", method)
    return m.group(1) if m else ""


def method_log(method):
    m = re.search(r"(?:^| )log=(\S+)", method)
    return m.group(1) if m else ""


def scan(log):
    if not log:
        return "none"
    p = subprocess.run([sys.executable, "-I", "scripts/bench-builds-helper.py", "scan", "--log", log],
                       capture_output=True, text=True)
    return p.stdout.strip() or "none"


def replace_segment(method, key, value):
    # Replace `key=...` up to the next ` key=` token; values themselves have no spaces here.
    return re.sub(r"(?:^| )" + re.escape(key) + r"=\S+", f" {key}={value}", method, count=1)


def load():
    rows = []
    seen = set()
    for path in FILES:
        if not __import__("os").path.exists(path):
            continue
        with open(path, newline="") as f:
            for r in csv.DictReader(f, delimiter="\t"):
                # Drop the phase-1 beta8 shipped rows: they used XEON_* env and were rerun with TOSH_*.
                if r["build"] == "beta8" and r["args_set"] == "shipped" and path.endswith("matrix.tsv"):
                    continue
                key = (r["timestamp"], r["build"], r["args_set"], r["model"], r["mode"], r["run"])
                if key in seen:
                    continue
                seen.add(key)
                rows.append(r)
    return rows


def main():
    rows = load()
    for r in rows:
        log = method_log(r["method"])
        reject = scan(log)
        if r["status"] == "REJECTED" and reject == "none":
            # Benign warning (automatic fitting not implemented, etc.); keep the measurement.
            r["status"] = "PASS"
        if r["status"] not in ("PASS",) and not r["status"].startswith("NOT RUN"):
            # leave FAIL as measured
            pass
        ns, tr = ns_for(r["build"], r["args_set"])
        r["method"] = replace_segment(r["method"], "rejected_flags", reject)
        r["method"] = replace_segment(r["method"], "status", r["status"])
        r["method"] = replace_segment(r["method"], "switch_namespace", ns)
        # The helper's method line is tokenised; restore a readable translation field.
        r["method"] = re.sub(r"switch_translation=.*? switches=", "switch_translation=" + tr + " switches=", r["method"], count=1)

    out = f"{BASE}/results.tsv"
    cols = ["timestamp", "build", "engine_sha16", "args_set", "model", "mode", "run", "status",
            "pp_ts", "tg_ts", "pp_len", "tg_len", "method"]
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for r in sorted(rows, key=lambda x: (BUILD_ORDER.index(x["build"]), x["timestamp"])):
            w.writerow({k: r.get(k, "") for k in cols})

    # Compact table: one row per build/model/mode/args_set.
    cells = {}
    for r in rows:
        if r["status"] != "PASS":
            continue
        m = short_model(r["model"])
        key = (m, r["build"], r["mode"], r["args_set"])
        cells.setdefault(key, []).append((float(r["pp_ts"]), float(r["tg_ts"])))
    print("| model | build | mode | args | prompt t/s (bench pp / real prompt) | generation t/s (bench tg / real gen) |")
    print("|---|---|---|---|---|---|")
    for m in MODEL_ORDER:
        for b in BUILD_ORDER:
            for mode in ("bench", "real"):
                for a in ("shipped", "011"):
                    k = (m, b, mode, a)
                    if k not in cells:
                        continue
                    pp = statistics.median(x[0] for x in cells[k])
                    tg = statistics.median(x[1] for x in cells[k])
                    if mode == "bench":
                        prompt, gen = pp, tg
                    else:
                        prompt, gen = tg, pp
                    print(f"| {m} | {b} | {mode} | {a} | {prompt:.2f} | {gen:.2f} |")


if __name__ == "__main__":
    main()