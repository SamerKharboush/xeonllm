# 20: with the DFlash drafter, the 35B never makes the tool call

Type: bug · Status: needs-triage · Found: beta.7 stress test, 2026-11-11

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
