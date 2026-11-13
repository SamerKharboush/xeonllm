# 26: 35B with the DFlash drafter answers band1100 with a different first token (beta 8 only)

Type: bug (Mocca diagnose, orchestrator gates) · Status: done (not a regression; contract §4 amended) · From: beta 8 R3 stress group C (R3-C-RESULT.md)

ornith-1.0-35b-Q6_K, app launch (-ngl 99 -c 32768 -fa 1 --dynamic-moe on ...), shipped beta 8 (63eb2a01af361672):
tensor band16/band300/band1100 are byte-identical to beta.7. The draft mode (-md <stem>.dflash.gguf
--spec-type draft-dflash -ngld 99 -ctkd q8_0 -ctvd q8_0) gives band16/band300 identical, but band1100 starts
"Thinking Process:\n\n1.  **Analyze the Request:**" where tensor (beta 8 and beta.7) and beta.7's draft start
"Here's a thinking process:". Offset 0: the first token comes from the target's prompt pass, not from drafting.
Contract gates "draft identical-vs-tensor" and "identical-vs-previous" FAIL. Ticket 20's family (drafter
changes the target's output).
Differences in the logs (same app args both releases): dynamic-MoE plan ub=1024 in beta 8 vs 512 in beta.7;
card 0 free VRAM at drafter load 5193 vs 4600 MiB, expert quota 24 vs 14; beta 8 logs
"sched_reserve: op offload on: MTL1_Private compute buffer 273.04 MiB". Expert residency changes which experts
run on a card vs the host, so placement (and card 0's free VRAM, which the display shares) may move text.

## Diagnosis (Mocca, 2026-11-13; evidence/26/compare.txt, *.lines.txt)

Seven runs, ornith-1.0-35b-Q6_K, cells band16/band300/band1100, gate launch flags, one server at a time:
- d1 and d2 (shipped beta 8, draft, same setup) differ from each other: band300 271 vs 263 chars (both
  @73 vs tensor), band1100 274 vs 269. t1 (beta 8 tensor) differs from the morning's tensor gate run
  at band1100 @91. So the 35B's text is not reproducible run to run in either mode.
- b7d (beta.7's engine, draft, today) gives band1100 "Thinking Process:", the beta 8 gate's draft text.
- The expert quotas per card vary run to run (card 0: 24 in the gate run, 31, 36, 37 today; dmoe_init
  lines), as does the hot set (4.0-4.4 GiB); card 0's free VRAM depends on the display.
- Switch runs (moe: TOSH_OFFLOAD_MOE=1; nopo: --no-op-offload; ub512) are single samples inside that
  noise and prove nothing either way. In ub512 the plan line still reads ub=1024.
Verdict: placement-dependent nondeterminism of dynamic MoE, present in beta.7 too; not a beta 8
regression. Contract §4: byte-identity is reported, not gated, for dynamic-MoE launches.
Possible later work (not beta 8): a fixed-placement mode for reproducible text.
