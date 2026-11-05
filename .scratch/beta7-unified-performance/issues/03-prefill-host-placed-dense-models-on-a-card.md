# 03: prefill host-placed dense models on a card (op offload) and measure PCIe

Status: resolved (offload was never on; when on it computes garbage; not shipped; ticket 08)
Type: research
Spec: `../spec.md` (user stories 12-14). Survey: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` §3.6 and shortlist item 3.

## Problem

A dense model that does not fit the cards runs on the host. Its prefill there is slow:
- 27B Q8_0 at 4.9964 tok/s;
- 27B Q6_K at 5.97 tok/s on an 856-token prompt.

The pin's Metal backend can offload large-batch `MUL_MAT`/`MUL_MAT_ID` for weights held on the
host (`ggml-metal.cpp:850-863`). The app hides the cards on host placement (ticket 67's rule).
The PCIe host-to-card rate on this Mac has never been measured.

## What to do

1. **Copy rate.** A timed `ggml_backend_tensor_set` of 1 GiB to card 1, N=5.
2. **The A/B:**
   - 27B Q8_0 at `-ngl 0`, `GGML_METAL_DEVICE_INDEX=1`;
   - `llama-bench -p 2048 -n 0 -r 3` at `-ub {512,1024,2048}`, with and without `-nopo`.
3. **Prove offload happens first** (CLAUDE.md rule 2): GPU activity from `ioreg` Device
   Utilization, or the per-op log. If the `-nopo` cell shows the same activity, the control is
   inert and the run is void.
4. **The decode text must not change.**
5. **If it pays above the noise:** an app ticket so that host placement keeps one card visible for
   offload. The test seam is `ServerSettings.environment`.

## Must not

Run a model over one card's working set with every layer on that card. Here the weights stay on
the host (`-ngl 0`).

## Comments

### 2026-11-04: answer (orchestrator)

**1. Host-to-card copy rate, card 1: 10.98-11.25 GB/s (wall time).**
- The GPU-time rate is 11.32-11.57 GB/s.
- Method: `tools/metal-probe/hostcopy.swift`, a blit from a shared buffer into a private one,
  1 GiB in 64 MiB command buffers, the first full copy discarded.
- 5 processes of 5 reps each. Output: `evidence/03/hostcopy-card1.txt`.

**2. Op offload never happened on this engine.**
- The first A/B on the shipped engine found `-nopo 0` and `-nopo 1` the same:
  - batch 512: 10.11-10.84 tok/s;
  - batch 1024: 11.51-11.94 tok/s.
- The control was inert (CLAUDE.md rule 2). `GGML_SCHED_DEBUG=2` on Qwen3-0.6B at `-ngl 0` shows
  0 splits on MTL with or without `-nopo`.
- The cause is in the scheduler (`ggml-backend.cpp:1156`): it offloads only when the weight's
  backend is the LAST backend. This build registers `MTL, BLAS, CPU`, the host weights map to
  BLAS, and BLAS is not last.
- A fix (accept any CPU- or ACCEL-type backend) gives 755 MTL splits with offload on and 0 with
  `-nopo 1`, so the control then takes effect.

**3. With the fix, prefill is faster.**
- Method: dev engine `build-static` with the fix; gemma4-coding 12B Q8_0 at `-ngl 0 -t 12
  -p 1024 -n 0 -b 1024 -r 3`, `GGML_METAL_DEVICE_INDEX=1`, cells alternating.
- The first `-nopo 1` cell overlapped a local Swift build (sd 2.13).

| `-ub` | `-nopo 1` (host) tok/s | `-nopo 0` (offload) tok/s |
|---|---|---|
| 512 | 8.63 (sd 2.13, contaminated), 10.07 (0.39) | 20.89 (0.04), 20.90 (0.02) |
| 1024 | 11.28 (0.68), 11.80 (0.11) | 22.03 (0.004), 22.05 (0.01) |

**4. But the text is wrong, so it is not shipped.** Greedy completions after a 570-token prompt,
dev engine with the fix, card 1:

| model | offload on | offload off |
|---|---|---|
| gemma4-coding 12B Q8_0 | `<unused50>` repeated | "The text repeatedly states that a quick brown fox jumps over a lazy dog near the river bank." |
| Qwen3-0.6B Q8_0 | `@@@@@@@@` | coherent |
| Qwen3-4B Q4_K_M | word salad | coherent |

- The offloaded mat-mul path computes garbage on this fork's GCN build. It has never run here,
  because the scheduler bug kept it off. That is also why beta.6's text is correct.
- The scheduler fix is reverted in `vendor/`. The fixed file is kept as
  `evidence/03/ggml-backend.with-sched-fix.cpp`.
- Ticket 08 finds why offloaded mat-mul is wrong. Only after that can host placement keep a card
  for prefill.
- The fork's Dynamic MoE code lowers the offload threshold for mixed execution
  (`ggml-metal.cpp:854-859`). That offload never ran either. Ticket 08 must check the expert
  tier too.
