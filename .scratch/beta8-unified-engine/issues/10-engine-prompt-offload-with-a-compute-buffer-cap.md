# 10: engine: prompt offload on, with a compute-buffer cap

Type: task (Mocca)
Status: done in a worktree (diff in evidence/10; enters patches/ as core/0082 after the beta.7 tag)
Spec: `../spec.md`. Evidence: beta7 tickets 03 and 08.

## What
- The scheduler fix (`ggml/src/ggml-backend.cpp:1156`, beta7 `evidence/03/ggml-backend.with-sched-fix.cpp`):
  a host-side backend (CPU or ACCEL/BLAS) holding a weight qualifies for op offload.
- A guard: when op offload is on, the context decides **before allocating** whether a GPU backend's
  compute buffer would exceed a cap (default 1536 MiB, env `TOSH_OFFLOAD_MAX_COMPUTE_MB`). If so it
  turns op offload off for that context, logs one warning line naming the size and the cap, and
  reserves again. At llama-cli's default context gemma4 12B asked card 0 for 5371332608 bytes.
- The Mocca op test `tests/test-sched-offload.cpp` (beta7 `evidence/08/mocca-sched-fix-and-test.diff`).
- One new patch under `patches/llama/core/`.

## Gate (orchestrator)
- test-sched-offload and test-backend-ops MUL_MAT 0 failures on both cards.
- gemma4 12B -ngl 0: at -c 2048 offload stays on (text identical to off); at a context whose buffer
  would exceed the cap, offload turns off with the log line and no allocation above the cap is tried.
- The ticket 03 A/B again with the patch.

## 2026-11-07: done (orchestrator); Mocca's run produced nothing

Mocca (brief `briefs/10-offload-cap.txt`) ran its full time and ended in a repetition loop; its diff
was one `#include <cstdlib>`. The orchestrator wrote the guard: `src/llama-context.cpp`
`sched_reserve()`, after `resolve_fused_ops`, when `cparams.op_offload` and not `no_alloc`: sizes the
worst-case pp graph with `graph_reserve(..., split_only=true, sizes)` (→ `ggml_backend_sched_reserve_size`,
no allocation), takes the largest GPU-device backend, and if it exceeds `TOSH_OFFLOAD_MAX_COMPUTE_MB`
(default 1536) turns op offload off for the context and recreates the sched; logs either way.
Diff: `evidence/10/0082-offload-with-a-compute-buffer-cap.diff` (scheduler fix + guard + op test).

**Gate (card 1, `GGML_METAL_DEVICE_INDEX=1 -dev MTL0`, llama-cli `-ngl 0 -t 12 -st --temp 0 -n 64 -b 512
-ub 512`, the 30x Paris prompt, `TOSH_FA_AMD=1`, N=1 per cell, no gpuRestart):**

| cell | guard line | prompt t/s on / off | text on vs `--no-op-offload` |
|---|---|---|---|
| 0.6B -c 4096 | `op offload on: MTL0_Private compute buffer 62.32 MiB, cap 1536` | 198.2 / 180.9 | identical |
| 0.6B -c 4096, cap 50 | `op offload off: ... would be 62.32 MiB, cap 50` | 170.9 / 198.6 | identical |
| 4B -c 4096 | `op offload on: ... 100.98 MiB` | 57.5 / 31.9 | identical |
| gemma4 12B -c 2048 | `op offload on: ... 141.27 MiB` | 17.5 / 11.5 | identical |
| gemma4 12B default ctx | `op offload off: ... would be 5122.50 MiB, cap 1536` | 11.2 / 11.0 | identical |

No `failed to allocate` line in any cell. In the off cells the MTL0 MUL_MAT lines in the sched debug
come only from the sizing probe and llama-cli's memory-fit dry runs (all before the guard line); the
prompt rate equals the no-offload rate, so offload really is off.

**Open for review:** llama-cli's `--fit` dry runs (`no_alloc` contexts) size the graph with offload on
and estimated a 9253.50 MiB card buffer for the 12B; the guard does not run there (it allocates
nothing). If fit uses that estimate to pick a context, it may pick a smaller one than needed. The
app passes an explicit `-c`, so it is not affected; check before relying on `--fit` with offload.
