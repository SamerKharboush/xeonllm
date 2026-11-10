# Beta 8 spec: one engine across the Xeon, both D700s and 64 GB

Decisions: `issues/05-*.md` (grilled 2026-11-07). Every ticket below names its files, its test seam,
what must not run, its measured gate and its report contract. Mocca (`9router/Mocca`, variant high)
implements code tickets in a worktree and never commits; the orchestrator re-runs every gate, runs
every model on a GPU, and lands the work. CLAUDE.md's performance rules apply to every number.

## Safety rules carried by every brief
- Never a model >= 5905580032 bytes on one card; never all of a model >= 2x that on the cards.
- No Metal command buffer longer than ~100 ms; no `test-backend-ops -m perf`.
- No kernel reads a shared (host) buffer.
- Every GPU program under `perl -e 'alarm N; exec @ARGV'`; stop at any new gpuRestart report.
- Mocca uses card 0 only (`GGML_METAL_DEVICE_INDEX=0`, `-dev MTL0`) and models <= 3.3 GB on a card.
- Nothing touches the user's server on :8080, /Applications/XeonLLM.app or the user's defaults.

## Tickets

| # | ticket | who | blocked by |
|---|---|---|---|
| 10 | engine: prompt offload on, with a compute-buffer cap | Mocca, then orchestrator gates | - |
| 11 | app: a host-placed model names one healthy card for offload | Mocca, then orchestrator gates | 10 |
| 12 | gate: prompt offload on the 35B MoE (text + pp) | orchestrator | 10 |
| 13 | drafts sized to the verify curve (caps 4 card / 3 host, A/B) | Mocca code, orchestrator A/B | 11 |
| 14 | non-temporal prefetch in the AVX1 dot kernels (35B decode A/B) | Mocca code, orchestrator A/B | - |
| 15 | quantised KV on the cards' flash attention (measure) | orchestrator | - |
| 16 | a dense model across both cards and RAM answers zeros (ticket 68) | orchestrator | - |
| 17 | GCN mat-vec: per-op decode profile, then a load-shape kernel | orchestrator, then Mocca | - |
| 18 | bound each prefill command buffer's GPU time (the 11-07 panic) | Mocca, then orchestrator gates | - |
| 19 | flash attention off for deep prefill on GCN (measure) | orchestrator | 18 |
