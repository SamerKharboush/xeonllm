# What do the big-model-on-small-GPU projects actually do, and what of it runs here?

Type: research
Status: open

## Question

For each project below: what is its mechanism, mechanically, from its source code? What does it
require (API, instruction set, unified memory, OS)? What has it measured, and on what hardware?
Which of its ideas can run on this machine (Metal-only GCN 1.0, AVX1 Xeon, PCIe 3.0 at a measured
11.1 GB/s host-to-card, NVMe)?

- **Strata.** The repo has receipts: `evidence/strata-policy-not-code-2026-10-20.md`,
  `third-party-receipts-2026-10-21.md`.
- **FreeToken.**
- **"Cabilary".** The user's spelling; identify the project, and say so if it cannot be found.
  Candidates include Colibri.
- **AirLLM.**
- **mesh-llm** (distributed inference across machines).
- Any other 2025-2026 project that runs models larger than VRAM on small GPUs (layer or expert
  streaming, prefetch, compression).

For each, state the precise blocker or the portable form for this fork, and an expected effect
from the mechanism, not a borrowed number. Output:
`.scratch/beta8-unified-engine/research/02-big-model-small-gpu.md`.
