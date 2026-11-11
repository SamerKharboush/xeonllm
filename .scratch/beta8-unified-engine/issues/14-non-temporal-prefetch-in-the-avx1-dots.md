# 14: non-temporal prefetch in the AVX1 dot kernels
Type: task (Mocca code, orchestrator A/B) · Status: resolved (no effect resolved on the 35B; not shipped)
From llama-modchip (`_MM_HINT_NTA` in the dot loops). SSE prefetch only, AVX1 build, env switch to
A/B in one binary; bit-identical results; 35B host decode A/B N>=3 processes per side.

## 2026-11-11: implemented by Mocca, measured: no resolved effect, not shipped

Mocca (high) added `_mm_prefetch(..., _MM_HINT_NTA)` of the weight stream, `TOSH_CPU_NTA_DIST` bytes
ahead (default 512, 0 = off), in the AVX1 single-row dots for Q4_K, Q6_K, Q8_0 and the 0080 multi-row
kernels (diff `evidence/14/nta-prefetch-with-0080.diff`, against series + 0080). Gates, re-run by the
orchestrator: test-vec-dot-multi 36/36 identical at dist 0 and 512; CPU test-backend-ops MUL_MAT
2037/2037, MUL_MAT_ID 1025/1025; greedy text (0.6B) identical; 0 AVX2/FMA, 12 prefetchnta.

A/B, `evidence/14/ab.log`: Metal-off AVX1 llama-bench (series + 0080 + this), Ornith-1.0-35B Q6_K
(28514152288 bytes, MoE), `-ngl 0 -t 12 -p 0 -n 64 -r 3`, processes alternating, llama-bench warmup
discarded, the user's idle CPU llama-server resident:

| distance | tg64 per process (t/s, sd within process 0.03-0.27) |
|---|---|
| 0 (off), round 1 | 11.03, 10.90, 11.04 |
| 512 | 11.15, 10.99, 11.09 |
| 0 (off), round 2 | 11.00, 11.18, 11.09 |
| 2048 | 11.09, 10.94, 11.02 |

The off processes span 10.90-11.18; neither distance moves outside that. No resolved change; the
expert stream is not limited by cache pollution at this decode rate. Kept as evidence only.
