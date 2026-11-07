# 18: bound the GPU time of each prefill command buffer (the 2026-11-07 panic)

Type: bug (safety) · Status: in-progress (Mocca, variant max) · Priority: before beta.7 ships
Evidence: `evidence/gates-beta7/out/set/Qwen3-14B-Q4_K_M/*-layer.server.log`, panic
`Kernel-2026-11-07-144047.panic` ("no successful checkins from WindowServer ... in 120 seconds").

The beta.7 stress run (the app's launch of Qwen3-14B-Q4_K_M, layer split over both cards, -c 16384,
ubatch 512) panicked the Mac during the 8300-token band on ~5.5k cached tokens: 2048-token chunks
took 65-91 s, so each of the five command buffers of a batch graph (metal/0078) ran for seconds on
card 0, the display card. Same cell passed on beta.6: marginal, not new.

Engine: measure each command buffer's GPU time; split batch graphs on a discrete card into as many
buffers as keep each under a target (default 50 ms), from the previous batch graph's measured time.
App (after the measurement): a smaller ubatch where one node alone exceeds the target.
Gate: max command-buffer GPU ms logged per graph, card 1, before/after; then the 14B layer cell.
