# 14: non-temporal prefetch in the AVX1 dot kernels
Type: task (Mocca code, orchestrator A/B) · Status: ready
From llama-modchip (`_MM_HINT_NTA` in the dot loops). SSE prefetch only, AVX1 build, env switch to
A/B in one binary; bit-identical results; 35B host decode A/B N>=3 processes per side.
