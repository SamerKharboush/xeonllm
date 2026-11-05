# 08: an offloaded mat-mul (host weights, computed on a card) gives garbage

Status: needs-triage
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
