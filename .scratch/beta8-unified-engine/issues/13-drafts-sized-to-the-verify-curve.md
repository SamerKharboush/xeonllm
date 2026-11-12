# 13: drafts sized to the verify curve
Type: task (Mocca code, orchestrator A/B) · Status: done (no change needed)
Cap n-gram and MTP draft length at 4 on a card, 3 on the host (app launch args; `common/common.h:357-361`
defaults are 48-64). Optionally llama-modchip's n-gram predictor idea (ideas, not code). A/B per cap:
tok/s and acceptance, N>=3, kept only above noise.

## 2026-11-10: most of it is already in the app
- MTP: `Server.swift:1423` `mtpDraftWidth` passes `--spec-draft-n-max 1` on GCN/Vega (2 on RDNA, 2 for qwen4exp), already under the agreed cap of 4.
- n-gram drafting is never enabled by the app (no `--spec-type ngram*`), so the 48-64 defaults do not apply to app launches.
- Left: DFlash (`--spec-type draft-dflash`, no `--spec-draft-n-max` passed, engine default). That is an orchestrator A/B on the 35B expert tier with its drafter: n-max default vs 4 vs 3, tok/s and acceptance, N>=3 servers alternating. Code change is one argument after the A/B.

## 2026-11-12: DFlash is already capped at 3
The beta.7 stress launch of the 35B with its drafter logs `common_speculative_impl_draft_dflash: - n_max=3, n_min=0, p_min=0.00`
(`evidence/gates-beta7/out2/set/ornith-1.0-35b-Q6_K/ornith-1.0-35b-Q6_K-draft.server.log:448`): the engine default
is already within the cap of 4. Acceptance per position 0.857/0.786/0.714, mean accepted length 3.36, overall 0.825.
MTP is at 1-2, n-gram is never enabled. Every path is within the cap, so the ticket's change is not needed.
A 2-vs-3-vs-4 A/B was not run: it would load the 35B on both cards (card 0 included) for hours, for a choice inside the cap.
