# 18: bound the GPU time of each prefill command buffer (the 2026-11-07 panic)

Type: bug (safety) · Status: engine part done in a worktree (diff evidence/18/0082-*.diff); app ubatch and the 14B gate open · Priority: before beta.7 ships
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

## 2026-11-10: engine part (orchestrator; Mocca's three runs stopped after a few minutes with no usable diff)

Change (`ggml-metal-context.m`, diff `evidence/18/0082-bound-each-batch-command-buffer.diff`):
GGML_METAL_MAX_COMMAND_BUFFERS 8 -> 64; every buffer of a batch graph gets a completion handler that
adds its GPU time; when a graph's last buffer completes, a per-device estimate of GPU ps per
(token x node) is updated (takes a higher value at once, decays 1/16 per graph); the next batch graph
takes ceil(predicted / TOSH_MTL_CB_TARGET_MS) buffers (default 50 ms, 0 = today's layout), at least
TOSH_MTL_PREFILL_CB, at most 64; with no measurement yet it takes 64; the main thread's share is capped
at one buffer's share. TOSH_MTL_CB_STATS=1 logs `cb stats: n_tokens n_nodes n_cb max sum` per batch graph.
A warning fires once if one node averages over the target ("use a smaller ubatch").

Measured, card 1, Qwen3-4B Q4_K_M, -ngl 99 -c 8192 -b 2048 -fa on, TOSH_FA_AMD=1, one ~6000-token
prompt (`evidence/18/prompt6k.txt`), llama-cli, N=1 per row, generated text byte-identical in all rows:

| cell | longest command buffer over the prompt | prompt t/s |
|---|---|---|
| today (TOSH_MTL_CB_TARGET_MS=0), ub 512 | 4306.6 ms | 42.4 |
| bound 50 ms, ub 512 (first graph unmeasured, 5 buffers) | first graph 1473 ms, then 496.5 | 42.4 |
| bound 50 ms, ub 512, first graph at 64 | 496.6 ms (first graph 175.8) | 42.5 |
| bound 50 ms, ub 128, first graph at 64 | **126.9 ms** (first graph 39.7) | 43.1 |
| bound 50 ms, ub 512, -fa off | 1484 ms (first graph, before the fix), then <= 175.9 | **67.9** |

- The GPU time of one 512-token batch grows linearly with the cached context: 6.2 s at 0-512 to 17.7 s
  at 5.6k-6.1k (4B, card 1). At 64 buffers the floor is one heavy node (flash attention at depth),
  so the bound alone stops near 0.5 s at 6k; ub 128 brings it to 127 ms.
- **ub 128 costs nothing here:** llama-bench pp512 on the 4B, card 1, -fa 1 -r 3, two processes each,
  alternating: ub 512 83.00 ± 0.19 and 82.50 ± 0.03; ub 128 88.06 ± 0.06 and 87.98 ± 0.14 tok/s.
- **Flash attention off read the deep prompt 60% faster** (67.9 against 42.4 t/s, N=1, text identical).
  Not acted on: FA is required for quantised KV and decode was not measured. New ticket material.
- Gates on the new build, card 1: test-backend-ops MUL_MAT 1832/1832, FLASH_ATTN_EXT (TOSH_FA_AMD=1)
  1993/1993; decode (0.6B, -n 64) logs no cb-stats line; 0 AVX2/FMA mnemonics; no panic or gpuRestart.
- An apparent "hang" of the first run after each fresh build is the runtime Metal library compile
  (MTLCompilerService cpu_resource reports at those times), not the GPU.

Open: (1) the app passes `-ub 128` on card launches (and the 14B layer split) — a user decision, it
changes every card launch; (2) the 14B layer cell must be re-run, at a 4k prompt first with cb stats,
before the 8300-token band.
