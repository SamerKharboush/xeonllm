# 19: flash attention off for deep prefill on GCN?

Type: measurement (orchestrator) · Status: resolved (2026-11-12): FA off wins prefill, FA on wins decode; ticket 21 takes both · From: ticket 18 (2026-11-10)

With `-fa off` a ~6000-token prompt on Qwen3-4B Q4_K_M, card 1, `-c 8192 -ub 512`, read at 67.9 tok/s
against 42.4 with `-fa on` (TOSH_FA_AMD=1), text byte-identical (N=1 each, `evidence/18/faoff.*`,
`t0.*`). The FA kernel's cost grows with the cached context faster than the separate KQ/softmax/V path.

Measure, both cards, 0.6B / 4B Q4_K_M / 8B / 14B layer split (after ticket 18), FA on vs off:
pp at depths 0, 2k, 6k (llama-bench `-p 512 -d 0,2048,6144`), decode tg128 at the same depths,
N>=3 processes alternating, text vs FA on. Quantised KV needs FA, so a change can only be "FA off
for f16 KV on GCN when it wins at the measured depths". Report decode as carefully as prefill.

## 2026-11-12: result (Mocca, high; orchestrator re-ran one row) — `evidence/19/RESULT.md`

All 12 rows resolved on both models (0.6B Q8_0, 4B Q4_K_M; card 1; -ub 128; two processes per side):
flash attention off reads prompts faster at every depth (4B pp512: 93.5 vs 88.0 at d0, 79.2 vs 51.9 at
d2048, 60.2 vs 27.6 at d6144) and flash attention on decodes faster at every depth (4B tg128: 16.7 vs
15.7, 14.8 vs 10.8, 12.1 vs 6.6). Text byte-identical. The orchestrator's row agrees (`orchestrator-check.txt`).

The fork already routes prompt batches to the decomposed path under FA (`amd_prefill_decomposed`,
src/llama-graph.cpp), but blocks it for head 64/128 on 32- and 64-lane cards (`amd_prefill_fa_blocked`,
comment: "Head 64/128 beat the decomposed route at every depth on both wave widths"). With that block
off (`TOSH_FA_PF_DISABLE=1`), FA on reads 92.9 / 76.4 / 56.4 and decodes 16.7 / 14.8 / 12.1 tok/s: both
sides' best. Ticket 21 changes that default on 64-lane cards.
