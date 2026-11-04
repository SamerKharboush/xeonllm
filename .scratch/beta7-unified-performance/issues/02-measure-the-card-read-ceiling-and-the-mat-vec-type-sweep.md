# 02: measure the card's read ceiling and the mat-vec type sweep, before any layout change

Status: ready-for-human
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
