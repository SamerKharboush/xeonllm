# 25: -ngl 0 (CPU) greedy text differs from beta.7 on 6 models; GPU text does not

Type: bug (Mocca diagnose, orchestrator gates) · Status: done (expected behaviour, documented) · From: beta 8 R3 stress groups A and B

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

## Correction and Ternary (steps 25b-25e, 2026-11-13)

Correction: the earlier "`--no-op-offload` gives beta 8's text" was measured on 0.6B and 8B only (the 0083
models); it did not cover Ternary.
- 25b (evidence/25/w64-set): TOSH_FA_PF_W64=1 gives beta.7's text on every cell of 4B Q4_K_M, 4B Q6_K and
  14B. With 0.6B (w64) and 8B band16 (hunk-8b: the 0083 condition reverted, which is exactly what the
  knob neutralises), 0083 explains five of the six moved models.
- Ternary-Bonsai-2-27B-PQ2_0 is qwen35 with head 256, outside 0083. 25c was inconclusive (mixed tree,
  an unproven control). 25d (evidence/25/ternary-all5): all five new patches reverted gives beta.7; 0082
  added alone gives beta 8; 0082 removed alone from the full series gives beta.7; only its sched_reserve
  cap removed stays beta 8. Cause: 0082's scheduler rule letting a card take a host-weight MUL_MAT.
- 25e (evidence/25/ternary-offload), shipped beta 8, gate launch flags: `--no-op-offload` (nopo, nopo2;
  command line in nopo-cmd.txt) and GGML_OP_OFFLOAD_MIN_BATCH=100000 (mb; mb-env.txt) both give
  beta.7's text on all three cells; the base run gives beta 8's. Request times (cells.tsv, 64 completion
  tokens): band1100 236.0 s with offload, 414.1 s (nopo) and 416.7 s (mb) without; band300 161.3 vs
  234.7 / 232.8 s.
Verdict: both moves are intended route changes (0083: FA prefill on the CPU at -ngl 0; 0082: prompt
mat-muls on a D700 at -ngl 0), not correctness bugs. Contract §4 now allows a -ngl 0 text move only
when the opt-out restores the previous text; the beta 8 notes name both.
Open question, not a blocker: why the Qwen models at -ngl 0 do not visibly offload (no text change with
--no-op-offload). Not measured.
