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

### 2026-11-07: Mocca run 1 rejected; rows-per-wave was already tuned in-tree

- Brief `briefs/07-gcn-matvec.txt` (Mocca, high, worktree `xeonllm-wt-matvec`, card 0 only). No gpuRestart.
- Its diff (`evidence/07-mocca-rejected.diff`, not applied) adds env knobs that overwrite `nr0`/`nsg` after
  the kernel is chosen. On the w64 path `nr0` is baked into the kernel by its name suffix (`_r8`,
  `_L16r8`, `_L16r4`), so the knob makes the dispatch grid disagree with the kernel: rows can go
  uncomputed. Its step-1 description (Q4_K "default nr0=2 nsg=2") is the 32-lane path, not what a
  D700 runs. It ran no sweep, no text gate, and concluded "no repack needed" without a measurement.
- What the tree already holds (`ggml-metal-device.cpp:1783-1820`, `ggml_metal_library_get_pipeline_mul_mv`):
  Q4_K on 64 lanes uses one simdgroup with 8 rows (`_r8`), and 16 lanes per block (`_L16r8`) from
  12288 rows up (or k <= 2560 with >= 6144 rows), each choice with a measured comment; Q5_K uses
  `_L16r2`; Q6_K and Q8_0 have `ext` w64 kernels. So the cheap lever (rows per wave, lanes per
  block) has been walked already, and decode still moves 36-51 GB/s of weight bytes per second
  (beta8 ticket 09, both cards).
- Remaining levers, unchanged: (2) the load shape of the shipped `_r8`/`_L16r8` kernels (bytes per
  lane per load, contiguity per wave), then (3) a repacked buffer type. Step (1), a per-op decode
  profile, is still the first thing to do: it says how much of a token the mat-vec is at all.
