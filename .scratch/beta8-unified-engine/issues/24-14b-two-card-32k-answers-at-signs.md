# 24: Qwen3-14B layer split over both cards at -c 32768 sometimes answers "@@@@..." (pre-existing)

Type: bug (Mocca diagnose, orchestrator gates) · Status: closed for beta 8 (known issue, documented; not reproduced serially) · From: beta 8 R2 repro A/B and ticket 23

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

## 2026-11-12 diagnosis (Mocca, evidence/24/RESULT.md) — not reproduced, not isolated

Strictly serial (one GPU program at a time, orchestrator monitor clean): 0 TEXT BAD in 22 runs
(build-fa 53546683d2539c54: 10 at default ub, 4 at ub 128, 4 extra; beta.7 engine 1a68d3efcbf476e7: 4).
Across all recorded runs 3 bad of 40. Bad and good logs of the same engine differ only in timings and
warning order; no nan/failed/evict lines. '@' is token 31; a NaN argmax would give token 0 ('!'), so
this is not plain NaN logits. new-1's window (≈17:35-17:40) shows no second llama-server/bench in the
monitor; the user's own app was running during the day and cannot be ruled out as a GPU-memory neighbour.
Status: open, known issue for beta 8 notes. The repro gate now fails on such an answer (TEXT BAD), so a
release cannot pass with it unseen.

## Closed for beta 8 (2026-11-13, orchestrator)

Not reproduced in 22 strictly serial runs; the 3 bad of 40 all fall in windows where another GPU program
(the user's own app) may have held card memory. The launch needs -c 32768 on the 14B layer split over
both cards, which overcommits each card's working set; the app never launches it (its planner caps the
14B at 16384, stress group B). The repro gate fails on such an answer (TEXT BAD) and passed on the R1b
binaries ("text ok"). Named in the beta 8 notes as a known issue. Reopen if it appears in an app launch.
