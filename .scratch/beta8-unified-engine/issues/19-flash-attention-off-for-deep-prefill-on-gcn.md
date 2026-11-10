# 19: flash attention off for deep prefill on GCN?

Type: measurement (orchestrator) · Status: ready · From: ticket 18 (2026-11-10)

With `-fa off` a ~6000-token prompt on Qwen3-4B Q4_K_M, card 1, `-c 8192 -ub 512`, read at 67.9 tok/s
against 42.4 with `-fa on` (TOSH_FA_AMD=1), text byte-identical (N=1 each, `evidence/18/faoff.*`,
`t0.*`). The FA kernel's cost grows with the cached context faster than the separate KQ/softmax/V path.

Measure, both cards, 0.6B / 4B Q4_K_M / 8B / 14B layer split (after ticket 18), FA on vs off:
pp at depths 0, 2k, 6k (llama-bench `-p 512 -d 0,2048,6144`), decode tg128 at the same depths,
N>=3 processes alternating, text vs FA on. Quantised KV needs FA, so a change can only be "FA off
for f16 KV on GCN when it wins at the measured depths". Report decode as carefully as prefill.
