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
