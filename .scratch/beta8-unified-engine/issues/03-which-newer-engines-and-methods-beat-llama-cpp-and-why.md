# Which newer engines and methods beat llama.cpp, and which of their ideas can this fork mimic?

Type: research
Status: resolved

## Question

Since `engine-survey-2026-11-04.md`, which engines and methods are reported faster than llama.cpp
on any hardware? For each, what is the mechanism, which hardware was it measured on, and can its
idea be built in a Metal GCN 1.0 + AVX1 engine?

Cover at least:
- activation sparsity on CPU and GPU (PowerInfer-style hot/cold neurons, TEAL, CATS, Deja Vu);
- low-bit kernels with lookup tables (T-MAC, BitNet.cpp) and their SSE/AVX1 fallbacks;
- newer quant formats (QTIP/trellis, the IQK quants, EXL3) and their dequant cost on a 64-lane
  GPU;
- speculative methods (EAGLE-3, lookahead, n-gram, MTP heads) against the measured verify curve
  here (t(2)/t(1) about 1.4 on the host, beta7 ticket 04);
- KV-cache compression or offload;
- layer skipping and early exit;
- graph-level scheduling across heterogeneous devices (pipelining, overlap of PCIe copies with
  compute);
- any llama.cpp alternative claimed "much faster" in 2026.

Rank the ideas by expected effect on this machine, from the mechanism. Output:
`.scratch/beta8-unified-engine/research/03-newer-engines-and-methods.md`.

## Answer

**No engine reported faster than llama.cpp in 2025-2026 runs here.** Each needs one of:
- AVX2 or newer (janas, ik_llama, T-MAC, BitNet);
- AVX-512 FP16 (eLLM);
- CUDA (krasis, ExLlamaV3, QTIP);
- Vulkan on Linux or Windows;
- trained predictors and checkpoints (PowerInfer, Deja Vu, LayerSkip).

**Three ideas carry over, ranked by mechanism on this machine:**
1. **A GCN mat-vec layout** (beta7 ticket 07). The card reads about 205 GB/s, while decode moves
   37-52 GB/s, so the kernel is bound by neither memory nor ALU. Upstream's Vulkan backend agrees:
   more rows per workgroup on GCN (`ggml-vulkan.cpp:2879-2882`), and no integer-dot mat-vec for
   Q6_K because of its 2-byte alignment (`:6687-6691`).
2. **Short speculative drafts sized to the host verify curve.** With t(2)/t(1) at 1.42-1.47,
   break-even acceptance is about 0.45 at one drafted token and about 0.6 at three (algebra on the
   measured curve). The pin's n-gram defaults draft 48-64 tokens (`common/common.h:357-361`,
   checked by the orchestrator), which is wrong here. MTP GGUFs for the 27B and the 9B are on disk.
3. **Overlap the 35B's CPU experts with card work in Dynamic MoE** (14.4 ms of a 76 ms token).
   Port the idea of KTransformers' Expert Deferral, not its code. It is lossy (up to 0.5%), so do
   a lossless overlap first.

**Also found:**
- **No AVX1 code for the ternary and 2-bit dots** (TQ1_0, TQ2_0, Q2_0, PQ2_0, PTQ1_0;
  `arch/x86/quants.c:1376-1740`). That matters for ternary models on the host.
- **Activation sparsity (TEAL, CATS) means a rewrite**, with quality unmeasured.
- **Trellis quants buy capacity, not speed here.**
- **Layer-skip self-speculation and lookahead lose** on the verify curve.

**A correction this ticket forces (H0).** Every card-1 result from 2026-11-04 is suspect, because
card 1 failed its op tests that day:
- the read ceiling (~205 GB/s);
- the decode bytes rate;
- the PCIe copy (11.1 GB/s);
- "offload computes garbage" (beta7 08);
- the LFM3 garbage on the card.

Re-measure all of them on card 0: ticket 09.

Hypotheses H0-H9, each with a gate: `research/03-newer-engines-and-methods.md`.
