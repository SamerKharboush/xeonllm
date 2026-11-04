# 04: an AVX1 port of the core/0022 multi-row CPU dots

Status: ready-for-agent (step 0 is the orchestrator's; the port waits for it)
Type: task
Blocked by: step 0 below
Spec: `../spec.md` (user stories 15-18). Survey: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` §3.3 and shortlist item 4.

## Problem

`patches/llama/core/0022-cpu-expert-dots.patch` adds `ggml_cpu_get_vec_dot_multi`: one weight
block unpacked once and applied to 1-4 activation rows. Every x86 implementation, and the getter,
sit inside `#if defined(__AVX2__)`, and the getter returns NULL otherwise. On this Xeon (AVX,
F16C, no AVX2 or FMA) the multi-row path never runs.

## Step 0 (orchestrator): the verify-cost curve

- `llama-bench -ngl 0 -p 1,2,4,8 -n 0 -r 5` on the 35B Q6_K and the 27B Q8_0, with
  `GGML_CPU_NO_MULTI_DOT` unset and set.
- On today's AVX1 engine the two must be identical. That proves the switch is inert today.
- Record t(k)/t(1).

## What to build

- An `#elif defined(__AVX__)` branch for Q6_K, Q4_K and Q8_0 first.
- 128-bit integer code (SSSE3/SSE4.1 `pmaddubsw`/`pmaddwd`), with AVX used only for float
  accumulation. This is the split the pin's AVX1 `vec_dot` uses: `ggml-cpu/arch/x86/quants.c`,
  the `#elif defined __AVX__` branches.
- No FMA.
- The results must be bit-identical to repeated single-row `vec_dot` calls.
- The new code goes into the patch file; do not edit the vendored tree directly.

## Gates

- `test-backend-ops -b CPU`: 0 failures.
- 0 AVX2/FMA mnemonics in the built binaries.
- The step 0 cells again, with the switch now changing the path (confirmed by a log line).
- `scripts/check-patch-series.sh` applies the series at the pin.

## Comments
