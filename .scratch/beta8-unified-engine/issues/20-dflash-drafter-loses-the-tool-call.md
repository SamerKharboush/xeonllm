# 20: with the DFlash drafter, the 35B never makes the tool call

Type: bug · Status: done (does not reproduce on series 0001-0084; re-checked by the beta 8 stress) · Found: beta.7 stress test, 2026-11-11

`evidence/gates-beta7/out2/set/ornith-1.0-35b-Q6_K/`: the app's launch of Ornith-1.0-35B Q6_K (expert
tier) with its DFlash drafter (Qwen3.6-35B-A3B-DFlash-Q8_0) answers the tools cell ("What is the
weather in Lisbon? Use the tool.", one `get_weather` tool, tool_choice auto, temperature 0,
max_tokens 512) with 512 tokens and **no tool_calls**; draft acceptance for that request 0 of 24.
The same launch without the drafter (tensor cell) plans the call and makes it in 81 tokens.
Every other drafter cell passes (19 of 21; acceptance 0.825 elsewhere).

Greedy speculative decoding should give the same tokens as without the drafter, so the drafter
path changes the output here. Suspects: the tool-call grammar/lazy grammar with drafted tokens
(the grammar sampler is not applied to the draft, or a rejected draft leaves the grammar state
advanced); the DFlash head copy (spec/0073); the reasoning/thinking budget with drafts.

Do: reproduce with the shipped llama-server and `--spec-type draft-dflash` on and off, temperature 0,
the same request; diff the token streams; bisect grammar on/off (a request without tools but with
`response_format` json). Gate: identical text with and without the drafter on this request and two
other tool requests.

## 2026-11-12: does not reproduce on today's engine
- Mocca run 1 (brief 20): a `common/sampling.cpp` patch was REJECTED. It changes only `is_generated=false` callers
  (prompt replay `server-context.cpp:451`, synthetic drafts); real DFlash drafts are accepted with `true`, so it cannot
  affect this bug, and it would feed prompt tokens to the tool-call grammar. Its after-fix results were never saved.
  Diff kept in `evidence/20/mocca-rejected.diff`.
- Orchestrator, engine build-fa (series 0001-0084, unpatched), the failing request, temperature 0:
  - target `-ngl 0` + drafter on card 1: tool call made, 81 tokens (`evidence/20/orch/`).
  - the app's exact launch (`-ngl 99 -c 32768 --dynamic-moe on`, GGML_METAL_DEVICE_INDEX=1 + GGML_METAL_DEVICE_LIST=0,1,
    TOSH_AUTO_KV=auto): no drafter -> get_weather({"city":"Lisbon"}) in 81 tokens; drafter -> the same call in 70 tokens,
    draft acceptance 12/27 (`evidence/20/dmoe/o1-*`, `o2-*`).
- Residual: with the drafter the reasoning is a strict prefix of the no-drafter reasoning (identical for 170 chars,
  then it closes one sentence earlier). The two launches planned different Dynamic MoE hot sets (2.9 vs 3.1 GiB), so
  the expert arithmetic is not the same. Not the beta.7 failure (no call at all).
- Likely fixed by metal/0084 (GDN state fusion off across two cards; the 35B is qwen35moe with GDN layers and the
  beta.7 engine lacked it). Not proven by bisection. Mocca run 20b failed to load (the brief omitted
  GGML_METAL_DEVICE_INDEX=1: orchestrator error) and is kept as-is.
