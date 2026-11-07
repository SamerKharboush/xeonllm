# 08: an offloaded mat-mul (host weights, computed on a card) gives garbage

Status: resolved (does not reproduce on healthy cards; the 11-04 garbage was measured on card 1 the day it was faulty; offload stays off until the ticket 03 A/B and a compute-buffer bound)
Type: bug
Opened by: ticket 03

## Problem

With op offload actually enabled (the scheduler fix in
`evidence/03/ggml-backend.with-sched-fix.cpp`), a model at `-ngl 0` with card 1 visible computes
every large-batch MUL_MAT on the card from a host copy of the weights. The output is garbage on
every model tried:
- gemma4 12B Q8_0;
- Qwen3-0.6B Q8_0;
- Qwen3-4B Q4_K_M.

Host-only text is correct. The same models are correct with every layer on the card, so the kernels
themselves work. Suspect the difference between a weight in the model's own private buffer and the
scheduler's temporary copy of it:
- alignment or padding (the "aligned mat-vec reads" rule for gfx600);
- the w64 mul_mm path's expectations of the source buffer;
- a missing synchronisation between the copy and the kernel.

## What to do

1. **Reproduce at the op level.** Write a test that runs one MUL_MAT whose src0 sits in a CPU
   buffer through `ggml_backend_sched` with op offload on, and compare it with the CPU result.
   `test-backend-ops` cannot do this: it allocates src0 on the backend.
2. **Bisect:**
   - `TOSH_MV_ALIGN=0` and `TOSH_MV_ALIGN=1`;
   - the type (f16, q8_0, q4_K);
   - `-ub 32` and `-ub 512`;
   - card 0 and card 1.
3. **Fix the patch at fault, or refuse offload on 64-lane GPUs** in
   `ggml_backend_metal_device_offload_op`, with a log line.

## Gate

- The op test passes on both cards.
- Greedy text with offload equals the host text over 64 tokens on the three models above, at
  agreement within the measured CPU-vs-GPU noise. Byte equality is not required, because the
  backends sum in a different order.
- Then the A/B of ticket 03 again.

## Comments

### 2026-11-07: does not reproduce after the second cold cycle; the fault was most likely card 1's

Mocca (9router/Mocca, high) worked the brief `briefs/08-offload-garbage.txt` in the worktree
`xeonllm-wt-offload` (731b358fd, the series without 0079/0080, neither touches this path), on card 0
only, and hit the 2 h limit without a report. Its diff, kept as `evidence/08/mocca-sched-fix-and-test.diff`:
the scheduler fix (`ggml-backend.cpp:1156`, identical to `evidence/03/ggml-backend.with-sched-fix.cpp`)
and a new op test `tests/test-sched-offload.cpp` (a MUL_MAT whose weight sits in a CPU WEIGHTS buffer,
run through `ggml_backend_sched` with op offload on, against the CPU result by NMSE). I re-ran
everything below myself, on card 1 (`GGML_METAL_DEVICE_INDEX=1`, `-dev MTL0`), which passed
test-backend-ops 13983/13983 the same night.

- **Op test, card 1:** `test-sched-offload` 60 cases (f32, f16, q8_0, q4_K, q6_K; several N and M),
  every one `offload=yes ... accel=MTL0` and `ok`, NMSE 1.7e-07 to 1.6e-05; `SUCCESS: 0 failure(s)`.
  Mocca got the same on card 0, and `test-backend-ops -b MTL0 -o MUL_MAT` 1832/1832 on card 0.
- **Text, card 1**, llama-cli sha256 `2dbeb374f2ed25c5`, `-ngl 0 -t 12 -st --temp 0 -n 64 -b 512 -ub 512`,
  the 30x "history of Paris" prompt (as ticket 03), `TOSH_FA_AMD=1`, offload on vs `--no-op-offload`:

  | model | MUL_MAT lines on MTL0 (GGML_SCHED_DEBUG=2), on / off | generated text on vs off |
  |---|---|---|
  | Qwen3-0.6B Q8_0, -c 4096 | 1158 / 0 | byte-identical (313 bytes) |
  | Qwen3-4B Q4_K_M, -c 4096 | 1494 / 0 | byte-identical (309 bytes) |
  | gemma4 12B Q8_0, -c 2048 | 2064 / 0 | byte-identical (290 bytes) |

  The control takes effect: the "on" runs place the prompt MUL_MATs on the card, the "off" runs none.
  The text is coherent in every cell. No gpuRestart before, during or after.
- **Why ticket 03 saw garbage:** not proven. Ticket 03's runs (2026-11-04) were on card 1, the day the
  card was found computing wrong answers (beta8 ticket 01; it recovered only after a cold power-off).
  Same scheduler fix, same series; the card's state is the one difference I can name.
- **Safety finding (must gate any shipping of offload):** with offload on and llama-cli's default context
  (the model's full trained context), gemma4 12B at `-ngl 0` asked card 0 for a 5371332608-byte
  `MTL0_Private` compute buffer (log: `failed to allocate buffer, size = 4520.00 MiB`). It failed cleanly
  this time, but that is 91 % of the 5905580032-byte per-card limit. At `-c 2048` the buffer is 141.27 MiB.
  Offload must ship with a bounded context/ubatch or a compute-buffer check.
- **Not shipped.** The scheduler fix stays out of the series. Next: the ticket 03 A/B (prefill on the
  card vs the host for a host-placed dense model) again, now that offload is both on and correct.
