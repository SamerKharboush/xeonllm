# 25: -ngl 0 (CPU) greedy text differs from beta.7 on 6 models; GPU text does not

Type: bug (Mocca diagnose, orchestrator gates) · Status: open · From: beta 8 R3 stress groups A and B

Contract section 4 gates "byte-identical to the previous release's text for the same prompt, model and
backend". Beta 8's ngl0 mode fails it: Qwen3-0.6B (band1100 @216), 4B Q4_K_M (@143), 4B Q6_K (@51),
8B (band16 @225), 14B (band300 @6), Ternary-Bonsai-27B (band300 @226). Nemotron passes; LFM3 has no beta.7
ngl0. Tensor and layer text are byte-identical to beta.7 on every model. In beta.7 the 0.6B's GPU and
CPU text were identical; in beta 8 GPU still equals beta.7 but CPU moved.
Same app args both releases (-ub 128 -b 128 -t 12 ...). `--no-op-offload` (stress mode ngl0nopo) gives
beta 8's text exactly, so it is not the prompt offload. Patches added since beta.7: core/0082 (prompt
offload + compute-buffer cap in sched_reserve + scheduler change), metal/0083, 0084, 0085, core/0086.

## Diagnosis (Mocca bisect, 2026-11-13; evidence/25/RESULT.md)

Cause: metal/0083 (`amd_prefill_fa_blocked` in `build_attn_mha`). The flag is keyed on the Metal device's
SIMD width, which is set whenever a D700 is registered, also at -ngl 0. Beta.7 blocked FA prefill on 64-lane
cards, so a CPU-only run took the decomposed route (KQ mat-mul, soft_max, AV mat-mul); beta 8 takes
`ggml_flash_attn_ext` on the CPU, the same route a build with no Metal device takes. Same attention,
different summation order (online softmax vs materialised KQ).
Proof: HEAD with only that hunk put back (`hunk`) and HEAD with `TOSH_FA_PF_W64=1` (`w64`) both give
beta.7's text on all three 0.6B cells; `hunk-8b` gives beta.7's 8B band16 text. Reverting 0082+0086
(`no82`) or 0085 (`no85`) changes nothing; `--no-op-offload` changes nothing. Determinism: each engine
reproduces its own reference when the three ngl0 cells run in the gate's order.
Verdict: legitimate reordering, not a correctness bug. Step 2 (25b) checks TOSH_FA_PF_W64=1 on the
other four moved models.
