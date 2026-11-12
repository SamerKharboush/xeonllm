#!/usr/bin/env python3
"""List 2-D weight tensors of a GGUF model, grouped by (name pattern, type, ne0, ne1)."""
import sys, re, json
from collections import OrderedDict

sys.path.insert(0, "/Users/sam/Library/Caches/xeonllm-wt-fa/gguf-py")

from gguf import GGUFReader
from gguf.constants import GGMLQuantizationType

PATTERNS = [
    ("attn_q",    re.compile(r"blk\.(\d+)\.attn_q\.weight$")),
    ("attn_k",    re.compile(r"blk\.(\d+)\.attn_k\.weight$")),
    ("attn_v",    re.compile(r"blk\.(\d+)\.attn_v\.weight$")),
    ("attn_out",  re.compile(r"blk\.(\d+)\.attn_output\.weight$")),
    ("ffn_gate",  re.compile(r"blk\.(\d+)\.ffn_gate\.weight$")),
    ("ffn_up",    re.compile(r"blk\.(\d+)\.ffn_up\.weight$")),
    ("ffn_down",  re.compile(r"blk\.(\d+)\.ffn_down\.weight$")),
]

def main(path):
    r = GGUFReader(path, "r")
    print("model:", path)
    for key in ("general.architecture", "qwen3.block_count", "qwen3.embedding_length",
                "qwen3.feed_forward_length", "qwen3.attention.head_count",
                "qwen3.attention.head_count_kv", "qwen3.vocab_size"):
        f = r.get_field(key)
        if f is not None:
            print(f"  {key} = {f.contents()}")

    groups = OrderedDict()
    other2d = []
    for t in r.tensors:
        if len(t.shape) != 2:
            continue
        ne0, ne1 = int(t.shape[0]), int(t.shape[1])
        ttype = t.tensor_type.name
        pat = None
        layer = None
        for name, rx in PATTERNS:
            m = rx.search(t.name)
            if m:
                pat = name
                layer = int(m.group(1))
                break
        if pat is None:
            other2d.append((t.name, ttype, ne0, ne1, t.n_bytes))
            continue
        key = (pat, ttype, ne0, ne1)
        g = groups.get(key)
        if g is None:
            g = groups[key] = {"layers": [], "bytes_each": t.n_bytes}
        g["layers"].append(layer)

    print()
    print(f"{'pattern':10s} {'type':6s} {'ne0':>6s} {'ne1':>6s} {'bytes':>12s} {'n_layers':>8s}  layers")
    total = 0
    rows = []
    for (pat, ttype, ne0, ne1), g in groups.items():
        ls = sorted(g["layers"])
        nb = g["bytes_each"]
        nbytes = nb * len(ls)
        total += nbytes
        lstr = f"{ls[0]}..{ls[-1]}" if len(ls) > 1 else str(ls[0])
        contig = (ls == list(range(ls[0], ls[0] + len(ls))))
        print(f"{pat:10s} {ttype:6s} {ne0:6d} {ne1:6d} {nb:12d} {len(ls):8d}  {lstr}{'' if contig else ' (NON-CONTIG)'}")
        rows.append(dict(pattern=pat, type=ttype, ne0=ne0, ne1=ne1, bytes_each=nb,
                         n_layers=len(ls), layers=ls, total_bytes=nbytes))
    print(f"\ntotal bytes over 2-D per-layer weight tensors: {total}")

    print("\nother 2-D tensors (not per-layer):")
    for name, ttype, ne0, ne1, nb in other2d:
        print(f"  {name:40s} {ttype:6s} {ne0:6d} x {ne1:6d}  {nb} bytes")

    return rows

if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)
        print("=" * 100)
