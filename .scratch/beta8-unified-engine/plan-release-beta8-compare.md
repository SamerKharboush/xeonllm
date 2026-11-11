# Plan: publish beta.7, finish beta 8, then compare beta 8 with ToshLLM on this Mac

Owner of the work: Mocca (`9router/Mocca`, variant high, via `opencode-delegate`), one brief per step.
Owner of the gates: the orchestrator (Claude). It reviews every diff, re-runs every gate, and is the
only one that decides when the GPU is free. Status lines below are updated as steps land.

## Rules for every step (they go into every brief)

- **One heavy job at a time on this machine.** Two freezes in four days (2026-11-07 deep prefill on
  card 0; 2026-11-10 a 24-thread build). A GPU step never runs while another GPU step or a build
  runs. Builds use at most 8 jobs.
- The GPU safety rules of `spec.md` (model sizes per card, `stat -L`, `perl -e 'alarm N'` around
  every GPU program, no shared-buffer kernels, stop at the first new panic/watchdog/gpuRestart
  report in /Library/Logs/DiagnosticReports).
- Never touch the user's llama-server on :8080 or the user's data (`dev.xeonllm.app`,
  `dev.engel.toshllm` defaults and their Application Support folders). Test launches use
  `dev.xeonllm.gatetest`.
- Every number follows CLAUDE.md "Performance claims": method line, N, no percentage against a
  modelled ideal, controls proven, never "faster" for a split-mode pair.

## A. Publish beta.7 (in parallel with B; CPU/network only)

| step | what | who | gate |
|---|---|---|---|
| A0 | stress test of the rebuilt app (contract §4), app gates (§5: DMG checks, one real chat) | orchestrator (GPU) | every cell passes or is named |
| A1 | release notes `dist/beta31b7-notes.md`, `dist/checksums-b7.txt`, README download block -> beta.7 | Mocca | orchestrator reads the notes against the gate logs |
| A2 | commit `release: 0.87.31-beta.7`, annotated tag, push the branch, the branch to `main`, the tag; `gh release create` (prerelease, 3 assets) | Mocca, only after the orchestrator says A0 passed | orchestrator checks the release page, asset sha256, tag commit |

## B. Finish beta 8 (one GPU ticket at a time, after A0)

Order: 12 (35B MoE prompt offload: text + pp) -> 19 (flash attention off at depth) -> 15 (quantised
KV) -> 13 (DFlash draft length A/B) -> 16 (dense 27B zeros across both cards + RAM) -> 17 (decode
profile, then a kernel). Offload patch core/0082 enters the series first (ticket 10, held until the
beta.7 tag). Each ticket: Mocca runs the measurement script the brief gives it and writes the table;
the orchestrator re-runs one cell of each table before it is accepted. Then beta 8: VERSION, notes,
engines (8 jobs), app, DMG, the full contract.

## C. Beta 8 against the original ToshLLM, same Mac, same models (after B)

- Install beta 8 into /Applications/XeonLLM.app (user asked for this); ToshLLM 0.87.33 is already in
  /Applications/ToshLLM.app (no-AVX2 build of the same llama.cpp pin d81235049, 0 AVX2/FMA).
- **Engine level** (same flags where both accept them; a flag one engine rejects is named in the
  method line): each app's bundled `llama-bench`, alternating ToshLLM / beta 8 processes, N >= 3,
  `-r 5`, warmup discarded. Models, small first: Qwen3-0.6B Q8_0, Qwen3-4B Q4_K_M, Qwen3-4B Q6_K,
  Qwen3-8B Q4_K_M, LFM3-1.7B F16 (ToshLLM cannot load it: named, not run). Cells per model: one card
  (card 1), pp512 / pp2048 / tg128; decode at depth 4096.
- **Whole machine** (each app's own placement and every optimisation it has, both cards, the Xeon,
  the 64 GB): the app's own launch arguments read from each app's server log for: Qwen3-14B Q4_K_M
  (both cards), gemma4 12B Q8_0 (too big for both cards: host + prompt offload in beta 8), the 35B
  MoE (host/expert tier), each through `/v1/chat/completions` with a 512-token and a 4k-token
  prompt, 128 tokens out, temperature 0; prompt t/s, decode t/s, text compared.
- Report: one table per level, method lines, no "x% faster than" against anything modelled; split
  modes never called faster than each other; ToshLLM's own defaults recorded from its log.
