# Which newer engines and methods beat llama.cpp, and which of their ideas can this fork mimic?

Type: research
Status: open

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
