# Map: beta 8, one engine across the Xeon, both D700s and 64 GB

Label: wayfinder:map

## Destination

A beta 8 spec, plus implementation tickets that Mocca can execute blind. Each ticket names its files,
its test seam and a measured gate. Together they make this machine run larger models faster, by
using the AVX1 Xeon, both D700s and the 64 GB of RAM as one pool. Nothing is built in this effort.

## Notes

- **Domain.** The XeonLLM fork of llama.cpp: pin `d81235049` plus the patch series. The machine is
  a Mac Pro 6,1:
  - Xeon E5-2697 v2: AVX and F16C, no AVX2 or FMA;
  - 64 GB DDR3, measured read ceiling 51.6 GB/s;
  - 2x FirePro D700 (GCN 1.0, 64 lanes, Metal only, no peer link): measured read ceiling
    204-206 GB/s per card, host-to-card copy 11.0-11.25 GB/s.
- **Every number obeys CLAUDE.md:**
  - a method line;
  - no percentage against a modelled ideal;
  - controls proven to take effect;
  - fits judged against 5x noise;
  - configurations that cannot run are named.
- **Safety rules (memory):**
  - no model over a card's working set on that card;
  - no all-on-cards model over both cards;
  - no GPU command buffer longer than ~100 ms;
  - this Mac rebooted three times on 2026-11-03/04 from GPU faults.
- **Prior work to read first:**
  - `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` (no AVX2-only engine
    runs here);
  - `.scratch/beta7-unified-performance/` (tickets 01-08 and their answers).
- **The user's standing choices:**
  - overclocking is **research only**;
  - Mocca (`9router/Mocca`, variant high) implements, and the orchestrator reviews and gates.
- **Skills:** `research` for research tickets; `grilling` + `domain-modeling` for grilling.

## Decisions so far

## Not yet specified

- How the four pools become one schedule: which tensors live on card 0, card 1 and host RAM, per
  model class (dense under 12 GB, dense over 12 GB, MoE), and how prefill differs from decode.
  This hangs on card 1's health, the offload bug (beta7 ticket 08), the zeros of a dense model
  split across both cards and RAM (beta7 06 / ticket 68), and what the research turns up.
- A GCN mat-vec layout (beta7 ticket 07): its shape depends on the research into newer kernels and
  repacking.
- Streaming weights larger than RAM from NVMe (the AirLLM / "LLM in a flash" class): whether it is
  worth anything here depends on the research and a measured NVMe rate.
- Whether to bump the llama.cpp pin for beta 8, or keep backporting (LFM3 needed a fix to the
  backport: upstream models no longer expand their own graph).

## Out of scope

- Shipping overclocking or voltage changes. Research only, by the user's choice: see the clock
  headroom ticket.
