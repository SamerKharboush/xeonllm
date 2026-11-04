# What do the big-model-on-small-GPU projects actually do, and what of it runs here?

Type: research
Status: resolved

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

## Answer

**None of the named projects runs on this machine.** Each blocker is in its own source:
- FreeToken: Linux with CUDA 13, or ROCm on RDNA3/4.
- mesh-llm: Apple Silicon only, and several machines.
- AirLLM: MLX on darwin.
- Strata: "Intel Macs cannot run it" (`docs/MAC.md:3-4`).
- moe-l2: CUDA only.
- flash-moe: Apple Silicon, one hard-wired model.
- Colibri's new Metal backend: written for unified memory, wrapping host pages zero-copy, so a
  D700 would read weights over PCIe.
- **"Cabilary" could not be identified**; the closest candidate is Colibri.

**The fork already does most of what they do:**
- a per-card expert arena (LFU and decay);
- CPU-computed misses;
- a locked RAM cache fed by `pread`;
- disk read-ahead;
- shared-event CPU/GPU handoff.

**Three gaps are left, which become the hypotheses:**
- **H1, a miss split.** Upload a share `f = p/(p+c)` of the expert misses to the card and compute
  the rest on the CPU (FreeToken, `moe/bench_profile.py:116-129`).
- **H4, a warm start for the VRAM arena** from a saved expert-heat file (Colibri,
  `qwen36_tier.c:1856-1875`).
- **H7, pipelined verify windows** across a layer split (mesh-llm), after ticket 68.

**Two numbers this machine has never measured decide several of these:**
- **H6:** the NVMe read rate.
- **H2:** a D700 reading host memory directly through a shared buffer. If it comes out at or
  below 51.6 GB/s, the zero-copy designs are out.

**H3:** count the distinct experts a k-token verify touches on the 35B. That count decides whether
any drafter can pay on the expert tier.

Lower priority: H5 (GPU prefill of host models, blocked by beta7 08) and H8 (lower-bit cold
experts, quality-gated). Each hypothesis has a method-line gate in `research/02-big-model-small-gpu.md`.

Spot-checked by the orchestrator: FreeToken `docs/install.md` ("Linux x86_64, NVIDIA GPU, driver
r580+ (CUDA 13)") and Strata `docs/MAC.md` ("Intel Macs cannot run it"), both in the clones under
`~/Library/Caches/beta8-research/`.
