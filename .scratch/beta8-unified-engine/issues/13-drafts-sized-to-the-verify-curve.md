# 13: drafts sized to the verify curve
Type: task (Mocca code, orchestrator A/B) · Status: ready (after 11)
Cap n-gram and MTP draft length at 4 on a card, 3 on the host (app launch args; `common/common.h:357-361`
defaults are 48-64). Optionally llama-modchip's n-gram predictor idea (ideas, not code). A/B per cap:
tok/s and acceptance, N>=3, kept only above noise.

## 2026-11-10: most of it is already in the app
- MTP: `Server.swift:1423` `mtpDraftWidth` passes `--spec-draft-n-max 1` on GCN/Vega (2 on RDNA, 2 for qwen4exp), already under the agreed cap of 4.
- n-gram drafting is never enabled by the app (no `--spec-type ngram*`), so the 48-64 defaults do not apply to app launches.
- Left: DFlash (`--spec-type draft-dflash`, no `--spec-draft-n-max` passed, engine default). That is an orchestrator A/B on the 35B expert tier with its drafter: n-max default vs 4 vs 3, tok/s and acceptance, N>=3 servers alternating. Code change is one argument after the A/B.
