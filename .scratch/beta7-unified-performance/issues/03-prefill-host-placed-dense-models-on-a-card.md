# 03: prefill host-placed dense models on a card (op offload) and measure PCIe

Status: ready-for-human
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
