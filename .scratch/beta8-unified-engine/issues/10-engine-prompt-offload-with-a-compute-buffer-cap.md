# 10: engine: prompt offload on, with a compute-buffer cap

Type: task (Mocca)
Status: in-progress
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
