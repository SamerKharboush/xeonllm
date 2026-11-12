# 24: Qwen3-14B layer split over both cards at -c 32768 sometimes answers "@@@@..." (pre-existing)

Type: bug (Mocca diagnose, orchestrator gates) · Status: open · From: beta 8 R2 repro A/B and ticket 23

The 0078 repro (gates-beta8/repro.sh: Qwen3-14B Q4_K_M, GGML_METAL_DEVICE_LIST=0,1, -ngl 99 -c 32768
--split-mode layer -fa auto, ~5.4k-token prompt, max_tokens 64, temperature 0) answered with
content "@@@@..." (64 '@', no reasoning) in:
- beta.7 engine (1a68d3efcbf476e7): b7-1, b7-2 (2 of 2), gates-beta8/out/repro-ab/
- ticket 23 build: new-1 (1 of 2), evidence/23/repro/
and with normal reasoning text in beta 8 shipped (4f72303829f6fdda) b8-1, b8-2, ship; b8w64-1; beta.7's
own gate runs (gates-beta7/out/repro-ship.out); ticket 23 w64-1, new-2.
Per metal/0078's note this launch overcommits each card (~6.9 GB vs 6.44 GB working set). "@" repeated
is the signature of NaN/garbage logits. The repro gate only checked HTTP 200 + no Timeout lines; it
must also check the answer text.
