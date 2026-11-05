# 07: a GCN mat-vec that reads closer to the card's rate

Status: needs-triage
Type: task
Opened by: ticket 02

## Problem

- One D700 reads 204.4-206.1 GB/s with a plain streaming kernel (ticket 02).
- Decode on the same card moves model bytes at 37.1-51.5 GB/s (Qwen3-0.6B Q8_0 to Qwen3-8B
  Q4_K_M).
- Decode is mat-vec bound, so the kernel, not the card, sets the decode rate.

## What to try, in order

1. **A CPU-timed per-op decode profile** (the GPU timestamps are unreliable here), to name the
   share of the mat-vec.
2. **The access pattern.** The `read4` kernel reaches the ceiling with 16-byte loads in a grid
   stride. Compare the shipped Q4_K/Q6_K mat-vec's loads (block layout, `nr0`, simdgroup reduce).
3. **A repacked buffer type for Q4_K/Q6_K** (a weight layout made for 64-lane coalesced 16-byte
   loads), selected only on `simd_width == 64`.

## Gate

- `test-backend-ops` 0 failures on both cards.
- Decode `llama-bench -p 0 -n 128 -r 5 -fa 1` on card 1, N >= 6 processes alternating against the
  unrepacked build in one session.
- Text byte-identical on the 4B and the 8B, 256 tokens greedy.
- Every GPU program keeps each command buffer short (the reboot of 2026-11-04 19:00).

## Comments
