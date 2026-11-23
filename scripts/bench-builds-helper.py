#!/usr/bin/env python3
"""Helper for scripts/bench-builds.sh: method lines, parsing, and real-generation driver.

Run with python3 -I. No process environment is read or printed.
"""
import argparse
import http.client
import json
import os
import re
import socket
import statistics
import sys
import time

REJECT = re.compile(
    r"unknown option|unrecognized option|invalid argument|unsupported option|"
    r"no such option|flag provided but not defined|unrecognized arguments|"
    r"error:\s*(unknown|unrecognized|invalid|no such|unsupported)|"
    r"cannot use|assertion failed|fatal error",
    re.I,
)
REJECT_LIMIT = 3


def clean(value):
    return " ".join(str(value).replace("\t", " ").split())


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return [line.rstrip("\n") for line in f if line.strip()]


def meta_map(path):
    out = {}
    for line in read_lines(path):
        if "\t" in line:
            k, v = line.split("\t", 1)
            out[k] = v
    return out


def quant_of(model):
    m = re.search(r"(?i)(Q[0-9][A-Za-z0-9_]*|F16|F32|BF16)(?=\.|$)", os.path.basename(model))
    return m.group(1) if m else "unknown"


def arg_value(argv, names):
    for i, token in enumerate(argv):
        for name in names:
            if token == name and i + 1 < len(argv):
                return argv[i + 1]
            if token.startswith(name + "="):
                return token.split("=", 1)[1]
    return ""


def cmd_labels(args):
    argv = read_lines(args.args)
    print(arg_value(argv, ["-p", "--prompt"]), arg_value(argv, ["-n", "--n-predict"]))


def cmd_method(args):
    meta = meta_map(args.meta)
    argv = read_lines(args.args)
    env = read_lines(args.env)
    switches = "none"
    if env:
        switches = ";".join(clean(x) for x in sorted(env))
    fields = [
        ("date_time", args.datetime),
        ("build", args.build),
        ("args_set", args.args_set),
        ("engine_sha16", meta.get("bench_sha16", "?")),
        ("engine_banner", meta.get("bench_banner", "?")),
        ("engine_server_sha16", meta.get("server_sha16", "?")),
        ("model", args.model),
        ("quant", quant_of(args.model)),
        ("mode", args.mode),
        ("args", " ".join(clean(x) for x in argv)),
        ("ctx", args.ctx or arg_value(argv, ["-c", "--ctx-size"]) or "not passed (engine default)"),
        ("batch", args.batch or arg_value(argv, ["-b", "--batch-size"]) or "not passed (engine default)"),
        ("ubatch", args.ubatch or arg_value(argv, ["-ub", "--ubatch-size"]) or "not passed (engine default)"),
        ("pp_length", args.pp_length or arg_value(argv, ["-p", "--prompt"]) or "server real prompt"),
        ("tg_length", args.tg_length or arg_value(argv, ["-n", "--n-predict"]) or "server benchTGClamped"),
        ("depth", args.depth or arg_value(argv, ["-d", "--depth"]) or "0"),
        ("split_mode", args.split_mode or arg_value(argv, ["--split-mode"]) or "none"),
        ("fa", args.fa or arg_value(argv, ["-fa", "--flash-attn"]) or "not passed"),
        ("kv", args.kv or (arg_value(argv, ["-ctk", "--cache-type-k"]) or "f16") + "/" +
                (arg_value(argv, ["-ctv", "--cache-type-v"]) or "f16")),
        ("threads", args.threads or arg_value(argv, ["-t", "--threads"]) or "not passed (engine default)"),
        ("switch_namespace", args.switch_namespace),
        ("switch_translation", args.translation),
        ("switches", switches),
        ("N", args.n),
        ("warmups_discarded", args.warmups),
        ("user_server_8080_present", args.port8080),
        ("rejected_flags", args.reject),
        ("status", args.status),
        ("note", args.note),
        ("log", args.log),
    ]
    print(" ".join(f"{k}={clean(v)}" for k, v in fields))


def cmd_scan(args):
    found = []
    for line in read_lines(args.log):
        if REJECT.search(line):
            found.append(clean(line)[:180])
            if len(found) >= REJECT_LIMIT:
                break
    print(" | ".join(found) if found else "none")


def cmd_bench(args):
    text = open(args.log, encoding="utf-8", errors="replace").read()
    def speed(test):
        pat = re.compile(r"(?<![A-Za-z0-9])" + re.escape(test) + r"(?![A-Za-z0-9])([^\n]*)")
        for line in text.splitlines():
            m = pat.search(line)
            if not m:
                continue
            n = re.search(r"([0-9]+\.[0-9]+)\s*(?:±|\+/-)", m.group(1))
            if n:
                return n.group(1)
        return ""
    print(speed(args.pp_test), speed(args.tg_test))


def cmd_real(args):
    # Exact prompt from Sources/Benchmarks/Benchmark.swift realPrompt (HEAD).
    prompt = (
        "A hash table stores key-value pairs in an array of buckets, using a hash "
        "function to map each key to a bucket index. Collisions are handled by chaining "
        "or open addressing, and the table resizes when the load factor grows. " * 10
        + "Given the data structure described above, write a complete Python implementation "
          "of a thread-safe LRU cache with get, put and eviction. Include docstrings and a "
          "short usage example."
    )
    def once(n_predict):
        body = json.dumps({
            "prompt": prompt,
            "n_predict": n_predict,
            "temperature": 0,
            "seed": 42,
            "cache_prompt": False,
        }).encode()
        c = http.client.HTTPConnection(args.host, args.port, timeout=args.timeout)
        c.request("POST", "/completion", body, {"Content-Type": "application/json"})
        r = c.getresponse()
        data = r.read()
        c.close()
        if r.status != 200:
            raise RuntimeError(f"HTTP {r.status}: {data[:200]!r}")
        obj = json.loads(data)
        t = obj["timings"]
        return (float(t["predicted_per_second"]), float(t["prompt_per_second"]),
                int(t.get("predict_n", 0)), int(t.get("prompt_n", 0)))

    for _ in range(args.warmups):
        once(64)
        print(f"warmup\tdiscarded", flush=True)
    reps = []
    for i in range(1, args.reps + 1):
        tg, pp, predicted_n, prompt_n = once(args.n_predict)
        reps.append((tg, pp))
        print(f"rep\t{i}\t{tg:.4f}\t{pp:.4f}\t{prompt_n}\t{predicted_n}", flush=True)
    if reps:
        print(f"median\t-\t{statistics.median([r[0] for r in reps]):.4f}\t"
              f"{statistics.median([r[1] for r in reps]):.4f}\t-\t-", flush=True)


def cmd_median(args):
    vals = []
    for token in args.values:
        try:
            vals.append(float(token))
        except ValueError:
            pass
    if vals:
        print(f"{statistics.median(vals):.4f}")


def cmd_free_port(args):
    for port in range(args.lo, args.hi + 1):
        s = socket.socket()
        try:
            s.bind(("127.0.0.1", port))
            s.close()
            print(port)
            return
        except OSError:
            s.close()
    print("no free port", file=sys.stderr)
    sys.exit(2)


def cmd_plan(args):
    text = open(args.file, encoding="utf-8", errors="replace").read()
    if not text.strip():
        print("unsafe\tno plan line recorded")
        return
    hit = None
    for line in text.splitlines():
        if re.search(r"(?i)plan", line) and re.search(r"(?i)vram\s*=", line):
            hit = line
            break
    if not hit:
        print("unsafe\tno plan+vram= line")
        return
    vals = []
    for m in re.finditer(r"vram\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*(GiB|MiB|GB|MB)", hit, re.I):
        n, unit = float(m.group(1)), m.group(2).lower()
        vals.append(n * (1024 if unit in ("gib", "gb") else 1))
    if not vals:
        print("unsafe\tplan line has no vram= size: " + clean(hit)[:160])
        return
    peak = max(vals)
    total = sum(vals)
    ok = peak <= args.card_mib and total <= args.total_mib
    print(("ok" if ok else "unsafe") +
          f"\t{clean(hit)[:180]} [peak {peak:.0f} MiB, sum {total:.0f} MiB]")


def cmd_plan35(args):
    text = open(args.file, encoding="utf-8", errors="replace").read()
    # dry-run writes a JSON object as the last line beginning with '{'.
    obj = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
    # Prefer the engine's own human plan line: it names the private VRAM this run takes.
    vals = []
    for m in re.finditer(r"vram\s*[=:]\s*([0-9]+(?:\.[0-9]+)?)\s*(GiB|MiB|GB|MB)", text, re.I):
        n, unit = float(m.group(1)), m.group(2).lower()
        vals.append(n * (1024 if unit in ("gib", "gb") else 1))
    if not vals and isinstance(obj, dict):
        # Old engines print no human plan line: read only the projected private VRAM,
        # not the physical card size or aggregate candidate tables.
        for m in re.finditer(r'"projected_vram_bytes"\s*:\s*([0-9]+)', text):
            vals.append(int(m.group(1)) / 1048576)
        for m in re.finditer(r'"projected_private_mib"\s*:\s*([0-9]+)', text):
            vals.append(float(m.group(1)))
    if not vals:
        print("unsafe\tno dry-run plan vram field")
        sys.exit(1)
    peak = max(vals)
    total = sum(vals)
    ok = peak <= args.card_mib and total <= args.total_mib
    print(("ok" if ok else "unsafe") +
          f"\tdry-run vram peak={peak:.0f} MiB sum={total:.0f} MiB")
    if not ok:
        sys.exit(1)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("method")
    for key in ("meta", "args", "env", "model", "mode", "build", "args-set", "datetime",
                "ctx", "batch", "ubatch", "pp-length", "tg-length", "depth", "split-mode",
                "fa", "kv", "threads", "switch-namespace", "translation", "n", "warmups",
                "port8080", "reject", "status", "note", "log"):
        m.add_argument("--" + key, default="")
    m.set_defaults(func=cmd_method)

    lb = sub.add_parser("labels")
    lb.add_argument("--args", required=True)
    lb.set_defaults(func=cmd_labels)

    s = sub.add_parser("scan")
    s.add_argument("--log", required=True)
    s.set_defaults(func=cmd_scan)

    b = sub.add_parser("bench")
    b.add_argument("--log", required=True)
    b.add_argument("--pp-test", required=True)
    b.add_argument("--tg-test", required=True)
    b.set_defaults(func=cmd_bench)

    r = sub.add_parser("real")
    r.add_argument("--host", default="127.0.0.1")
    r.add_argument("--port", type=int, required=True)
    r.add_argument("--n-predict", type=int, required=True)
    r.add_argument("--warmups", type=int, default=1)
    r.add_argument("--reps", type=int, default=3)
    r.add_argument("--timeout", type=int, default=600)
    r.set_defaults(func=cmd_real)

    med = sub.add_parser("median")
    med.add_argument("values", nargs="*")
    med.set_defaults(func=cmd_median)

    fp = sub.add_parser("free-port")
    fp.add_argument("--lo", type=int, default=18200)
    fp.add_argument("--hi", type=int, default=18299)
    fp.set_defaults(func=cmd_free_port)

    pl = sub.add_parser("plan")
    pl.add_argument("--file", required=True)
    pl.add_argument("--card-mib", type=int, default=5900)
    pl.add_argument("--total-mib", type=int, default=11800)
    pl.set_defaults(func=cmd_plan)

    p35 = sub.add_parser("plan35")
    p35.add_argument("--file", required=True)
    p35.add_argument("--card-mib", type=int, default=5900)
    p35.add_argument("--total-mib", type=int, default=11800)
    p35.set_defaults(func=cmd_plan35)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
