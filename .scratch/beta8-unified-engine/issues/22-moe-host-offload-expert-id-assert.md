# 22: 35B MoE at -ngl 0 aborts at pp2048 with op offload (GGML_ASSERT id < n_expert)

Type: bug (Mocca diagnose + fix, orchestrator gates) · Status: open · From: beta 8 R2 gate 3.3

The shipped beta 8 llama-bench, Ornith-1.0-35B Q6_K, `-ngl 0 -fa 1 -p 16,...,2048 -n 0 -r 1` (default
-b 2048 -ub 512, op offload on by default, card 0 = MTL0): six bands pass, pp2048 aborts in
`ggml_backend_sched_compute_splits` (ggml-backend.cpp:2193, the used-expert copy for an offloaded
MUL_MAT_ID with host weights): `GGML_ASSERT(id >= 0 && id < n_expert)`. beta.7 passed all seven bands.
New in beta 8: core/0082 makes op offload actually happen with BLAS registered (before it, nothing was
offloaded), so this upstream expert-copy path runs for the first time on this fork.
The app is not affected: a host-placed MoE gets `--no-op-offload` (ticket 12 exclusion).
Evidence: `evidence/gates-beta8/out/pp-35b-host.{csv,err}`, `gates-prefill.log`.
