# 23: metal/0083's decomposed prefill needs a size bound (14B at 32k context: 2x slower prompt, 7x slower decode)

Type: bug (Mocca code + measurement, orchestrator gates) · Status: open · From: beta 8 R2 repro A/B

Shipped beta 8, Qwen3-14B Q4_K_M layer split over both cards, -c 32768, default -ub 512, ~5.4k prompt
(gates-beta8/repro.sh), two processes per arm alternating: beta 8 prompt 8.73/8.74 tok/s, decode
0.49/0.49; beta.7 engine 17.17/17.12, 3.33/3.38; beta 8 with TOSH_FA_PF_W64=1 17.15, 3.39. Only the b8
runs log `op offload off: MTL0_Private compute buffer would be 2904.05 MiB`: the decomposed route
materialises KQ = n_tokens x n_kv x n_head floats; at ub 512 x 32768 x 40 heads that is ~2.7 GB on a
card already holding half the model. Ticket 21 measured only depth <= 6144.
Evidence: `evidence/gates-beta8/out/repro-ab/`, `R2-RESULT.md`.
