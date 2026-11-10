# 11: app: a host-placed model names one healthy card for prompt offload

Type: task (Mocca)
Status: done (2026-11-10; Mocca, reviewed; swift test 537, only the known MCP race)

## What
`Sources/Servers/Server.swift` `environment` (around line 779): today a host-placed model
(`placement == .host`) leaves the cards out. With ticket 10 it should name exactly one healthy card
(`GGML_METAL_DEVICE_INDEX`): card 1 (headless) first, card 0 if the launch check excluded card 1,
none if both are excluded. Dense models only; an MoE host placement stays card-free until ticket 12.
Tests in `Tests/XeonLLMTests.swift` beside the existing placement tests: an excluded card is never
named; both excluded -> none; MoE host -> none.

## Gate
`swift test` with no new failures; the orchestrator's real launch of gemma4 12B through the app's
argument and environment builder shows offload on the chosen card and correct text.
