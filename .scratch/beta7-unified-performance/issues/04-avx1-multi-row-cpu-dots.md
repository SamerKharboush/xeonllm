# 04: an AVX1 port of the core/0022 multi-row CPU dots

Status: resolved (port bit-identical and running; time change small, see 2026-11-05)
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

### 2026-11-04: step 0 (orchestrator)

Method:
- the shipped `llama-bench` (sha256 `82725c76...`, `d81235049` + 88 patches, AVX1 build);
- `-ngl 0 -nopo 1 -t 12 -p 1,2,4,8 -n 0 -r 5`, one process per model and switch setting;
- llama-bench discards its own warmup;
- the user's idle CPU-only 14B `llama-server` was resident;
- no GPU work ran;
- Mocca was working at the same time (remote model, no local build).

t(k) is the mean time to process k tokens in one batch, sd in brackets.

| model | switch | t(1) ms | t(2) ms | t(4) ms | t(8) ms |
|---|---|---|---|---|---|
| Ornith-1.0-35B Q6_K | unset | 103.99 (2.82) | 147.58 (2.69) | 224.50 (6.74) | 614.23 (27.84) |
| Ornith-1.0-35B Q6_K | `GGML_CPU_NO_MULTI_DOT=1` | 108.19 (2.26) | 164.86 (8.43) | 224.73 (8.97) | 627.35 (35.61) |
| gemma4-coding 12B Q8_0 | unset | 299.15 (4.28) | 439.43 (18.87) | 675.83 (55.02) | 1206.06 (68.69) |
| gemma4-coding 12B Q8_0 | `GGML_CPU_NO_MULTI_DOT=1` | 298.04 (2.80) | 429.05 (24.05) | 646.76 (8.07) | 1244.26 (92.15) |

- **The switch.** For gemma, set and unset agree within one sd at every k. For the 35B they agree
  within one sd at k=4 and differ by 1.4 sd at k=1. At k=2 and k=8 they differ by about two sd,
  and the set runs ran second. This is consistent with an inert switch, which the code says it
  is: the getter returns NULL without AVX2.
- **The curve is not linear.** t(2) is about 1.4-1.5 x t(1), and t(4) about 2.2 x. Verifying a
  few drafted tokens on the host already costs much less than that many single tokens, which
  corrects the survey's "verification scales about linearly with k". On the 35B, t(8) jumps to
  5.9 x: eight tokens route to more distinct experts, so more weight bytes are read. The dense
  12B does not jump (4.0 x).
- **The port.** It shares the unpack work across k rows, so it can only lower t(k) for k >= 2 on
  the weights it covers (Q6_K, Q4_K, Q8_0). How much is unknown until measured. The port goes
  ahead; its gate is these same cells with the switch taking effect.

Evidence: `evidence/04/step0.sh`, `step0.out`, `*.err`.

### 2026-11-05: the port (Mocca, reviewed by the orchestrator)

`patches/llama/core/0080-cpu-expert-dots-avx1.patch`: `#elif defined(__AVX__)` multi-row kernels for
Q6_K, Q4_K and Q8_0. They use 128-bit SSSE3/SSE4.1 integer ops and 256-bit AVX float accumulation,
with no FMA. They follow the single-row AVX1 branches operation for operation, with only the unpack
of the weight block shared. The getter prints `ggml_cpu: multi-row dot ON for <type> (AVX1)` once
per type. The patch adds `tests/test-vec-dot-multi.cpp`. The series applies 90 of 90 at the pin.

Gates, run by the orchestrator:
- `test-vec-dot-multi`: 36 of 36 cases identical (memcmp), for Q6_K, Q4_K and Q8_0 with n in
  {256, 4096, 5120} and nc in 1..4. The ON line printed for all three types. Exit 0.
- AVX2/FMA mnemonics (vfmadd, vpbroadcast, vperm, vinserti128, ymm integer ops) in llama-bench,
  llama-cli and the test: 0.
- 35B Q6_K, host only, greedy, 28-token prompt, 48 tokens: the text is byte-identical with the
  switch unset and set. The ON line appears only when unset, so the control takes effect.

Verify-cost cells (`evidence/04/port.sh`, `port.out`):
- Method: the CPU-only AVX1 build of the worktree (sha256 `9798b6032b48f2f6`) on Ornith-1.0-35B Q6_K,
  `-ngl 0 -t 12 -p 1,2,4,8 -n 0 -r 5`, llama-bench discarding its own warmup.
- 2 processes per switch setting, alternating. The user's idle 14B `llama-server` was resident, and
  RustDesk was using about half a core.

t(k) in ms, with sd in brackets:

| process | t(1) | t(2) | t(4) | t(8) |
|---|---|---|---|---|
| unset 1 | 105.70 (0.84) | 150.56 (6.81) | 251.05 (11.69) | 588.96 (14.08) |
| set 1 | 106.15 (1.51) | 153.16 (7.70) | 225.95 (15.72) | 655.53 (45.11) |
| unset 2 | 102.94 (1.84) | 148.25 (3.22) | 216.58 (4.79) | 612.49 (42.59) |
| set 2 | 106.18 (2.21) | 159.29 (3.12) | 244.33 (14.11) | 669.58 (42.20) |

- **k = 1 to 4:** the two settings overlap; no change is resolved.
- **k = 8:** both unset processes (589, 612) are below both set processes (656, 670). The gaps are
  43-81 ms, with per-process sd of 14-45 ms. That is small and only about 1-2 sd per pair. It is two
  observations per side, not a measured gain.

The expert dots are not the dominant cost of a host verify on the 35B. The port stays in: it is
correct, it runs, and it costs nothing at k = 1.
