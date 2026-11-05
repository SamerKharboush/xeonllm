# 02: measure the card's read ceiling and the mat-vec type sweep, before any layout change

Status: resolved (ceiling measured; sweep instrument invalid; kernel ticket 07 opened)
Type: research
Spec: `../spec.md` (user stories 8-11). Survey: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` §3.1 and shortlist item 2.

## Problem

The D700's shipped Q6_K/Q4_K decode mat-vec reads 37-43 GB/s at large shapes, and 50-66 GB/s
with the `nr0=8` variants. The host's measured read ceiling is 51.6 GB/s. What one card can
read at most has never been measured (firellama-maxperf ticket 19). The per-op table that put the
35B dense mat-vec at 39.6 ms of a 78 ms token predates patches 0071, 0072 and 0074, so it is
stale.

## What to do

1. **Read ceiling.** A read-only Metal kernel over a buffer of at least 1 GiB on card 1, with a
   soak of at least 1 s, N=5 processes. Report GB/s with the buffer size and sd.
2. **Type sweep.** `test-backend-ops perf -o MUL_MAT -b MTL0` for q4_0, q8_0, iq4_nl, q4_K, q5_K
   and q6_K, at the 35B and 8B shapes (patch `moe/0070` adds them). Confirm the pipelines with
   `TOSH_SWEEP_DEBUG=1`. N=5.
3. **The per-op decode table re-taken on beta.6** (`TOSH_OPGPU=1`, patch `moe/0049`).
4. **Decide, and write the decision here:** a repacked GCN buffer type for the Q6_K/Q4_K
   mat-vec, only if the ceiling or the simple formats show room. If so, open a new ticket.

## Gate

- Every number carries a method line.
- A rate goes beside the ceiling only as two observations, never as a percentage of it
  (CLAUDE.md rule 1).

Why human: GPU runs on the display card's neighbour; the orchestrator runs them.

## Comments

### 2026-11-04: answer (orchestrator)

**1. The read ceiling of card 1: 204.4-206.1 GB/s** (`read4`, 1e9 bytes/s).
- Method: `tools/metal-probe/readceiling.swift`, a grid-stride xor over a 1 GiB private buffer,
  filled first.
- One pass per command buffer. The soak is at least 1.5 s per variant, with at most 400 passes and
  one warmup pass discarded. 5 processes ran; process 2 stopped itself on a zero GPU timestamp.
- Per variant, over the 4 good processes:

| kernel | threadgroups x threads | GB/s |
|---|---|---|
| `read4` | 1024 x 256 | 204.42-205.47 |
| `read4` | 4096 x 256 | 206.02-206.06 |
| `read4` | 512 x 64 | 204.84-205.14 |
| `read1` | 1024 x 256 | 190.96-191.12 |
| `read1` | 4096 x 256 | 201.56-201.76 |

- Three differently shaped `read4` variants land on the same rate, so the limit is the card's,
  not the kernel's. The narrower `read1` loads reach 191-202.
- Output: `evidence/02/readceiling-card1.txt`.

**Two safety findings:**
- The first version of this probe put a soak of 1.5 s or more into one command buffer. The Mac
  rebooted with a CPU machine check on the D700's PCIe config space (`IA32_MC20_ADDR=0xE02003C0`,
  2026-11-04 19:00).
- The GPU sometimes returns `gpuEndTime - gpuStartTime = 0`. Process 2 hit that here. A soak
  scaled from such a timing is what can queue seconds of work.
- The probe is now bounded: one pass per buffer, a 0.2 s per-buffer limit, and an abort on a zero
  timing.

**2. The type sweep: `test-backend-ops perf` is not a valid instrument on this card.** The same
4096 x 14336 mat-vec gave these per-run times:

| type | run | us/run |
|---|---|---|
| q4_0 | 1 | 2272.36 |
| q4_0 | 2 | 9087.06 |
| q4_0 | 3 | 6.55 |
| q4_K | 1 | 9095.89 |

6.55 us would be a read of 5 TB/s. Observations this far apart are not one quantity (CLAUDE.md
rule 3), so none of the four is quoted as a rate. The likely cause is the same unreliable GPU
timestamp; UNVERIFIED. Outputs: `evidence/02/mv-sweep*.txt`.

**In its place, end-to-end decode on card 1.**
- Method: the shipped `llama-bench` (`d81235049` + 88 patches), `GGML_METAL_DEVICE_INDEX=1
  TOSH_FA_AMD=1 -ngl 99 -p 0 -n 128 -r 5 -fa 1`, one process per model, warmup discarded by
  llama-bench.
- "bytes x tok/s" is the model file's bytes times tokens per second. It is a lower bound on what
  the kernels read, since it spreads all the bytes over the whole token, non-mat-vec ops included.

| model | tg128 tok/s (sd) | bytes x tok/s |
|---|---|---|
| Qwen3-0.6B Q8_0 | 58.631 (0.100) | 37.1 GB/s |
| Qwen3-4B Q4_K_M | 16.708 (0.007) | 41.6 GB/s |
| Qwen3-4B Q6_K | 13.914 (0.004) | 45.9 GB/s |
| Qwen3-8B Q4_K_M | 10.249 (0.001) | 51.5 GB/s |

Output: `evidence/02/tg-card1.txt`.

**3. The per-op decode table: not re-taken.** It reads the same GPU timestamps found unreliable
above, so it would carry the same doubt. Re-take it only with a CPU-side timer around each
command buffer.

**4. Decision.** The card reads about 205 GB/s, and decode on it moves model bytes at 37-52 GB/s.
These are two separate observations, not a ratio. Mat-vec kernel work has room, so ticket 07 is
opened for a GCN mat-vec that reads closer to the card's rate.
