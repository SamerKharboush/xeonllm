# 75: the placement rule ignores the KV cache on the card path

Status: open (needs-triage)
Type: task

## Problem

`Estimator.prefersHostPlacement` decides card versus host from the weights alone. The KV cache
is computed in the same function, but only for the host check.

`Sources/Hardware/Hardware.swift:475-484`:

    let budget = vramBudgetGB ?? usableVRAM(hw: hw, splitting: false, devices: 1)
    guard budget > 0 else { return false }
    // The weights are what the card has to hold. The KV cache and the compute
    // buffers follow them: a model whose weights do not fit is a card path that
    // streams the model over the bus on every token.
    guard spec.weightsGB > budget else { return false }
    // and the host has to hold it, or the host is not a fallback either
    let kvGB = kvCache(spec: spec, ctx: ctx) * kvScale
    let need = spec.weightsGB * 1.03 + kvGB + 0.9 + spec.paramsB * 0.012
    return need <= hw.ramGB * 0.72

Line 480 is the card decision: weights against the whole budget. Lines 482-483 build the same
sum with the KV cache and the compute buffers and only compare it against host RAM. The
caller passes the combined budget when the run splits across cards
(`Sources/Servers/Server.swift:227-230`), so a layer split can pass the card check with weights
that fit across both cards while each card holds weights plus its share of the KV cache plus
compute.

### The 14B at the app's launch (measured 2026-11-02)

Launch: Qwen3-14B-Q4_K_M, `-ngl 99` (`Sources/Servers/Server.swift:359`, default 99 in
`Sources/Settings/SettingsTab.swift:30`), `-c 32768` (`Sources/Servers/Server.swift:360`), f16 KV
(the `-ctk`/`-ctv` flags are only added when the type is not f16,
`Sources/Servers/Server.swift:386-387`), `--split-mode layer`, both cards.

The card check: `usableVRAM(splitting: true, devices: 2)` is 12 GiB combined (2 x 6144 MiB,
`Sources/Hardware/Hardware.swift:31-33`) less 1 GiB per card
(`Sources/Hardware/Hardware.swift:457-459`) = 10 GiB. The 14B Q4_K_M is 8.38 GiB
(`Tests/XeonLLMTests.swift:586`). 8.38 <= 10, so line 480 keeps it on the card.

What each card then holds:

| per card | MiB |
|---|---|
| weights (MTL0) | 3954 |
| KV cache, 32k f16 | 2688 |
| compute | 284 |
| total | 6926 |
| `recommendedMaxWorkingSetSize` | 6144 |

That is 782 MiB over the working set of each card, so the driver pages. The prefill watchdog
kill that follows is handled by metal/0078 (`../evidence/metal-0078-prefill-command-buffers-2026-11-02.md`);
the overcommit is not.

The whole-run sum that line 483 already computes, with the 32k heuristic KV
(`Sources/Hardware/Hardware.swift:534-541`, 0.08 GB per 1k tokens at 14B): 8.38 x 1.03 + 2.56 +
0.9 + 14.8 x 0.012 = 12.27 GiB against the 10 GiB budget. So `Estimator.estimate` knows the run
does not fit and returns level `.slow` on the partial-offload branch
(`Sources/Hardware/Hardware.swift:387-393`), while the placement field keeps its `.card` default
(`Sources/Hardware/Hardware.swift:203`). Only the card-vs-host decision misses it.

## Options

1. **Count weights + KV + compute against the budget, not the weights alone.** The arithmetic
   already exists at `Sources/Hardware/Hardware.swift:377`; the card decision would use it with
   the same budget it has now, instead of the weights-only guard at line 480. The 14B at 32k is
   over on either reading (12.27 GiB against 10 GiB combined; 6926 MiB against 6144 MiB per
   card), so it flips to `.host`.
   Trade-off: the host path is chosen for a model that does load and answer today with
   metal/0078, and this fork has no decode row for a dense 14B on the host, so the choice is
   based on churn (paging) rather than a measured pair. Needs a measurement of both sides
   before the rule flips.
2. **Keep the card, make the run fit.** When weights + KV + compute per card is over the working
   set, lower `ctx` or pick a q8_0 KV for the launch. Per card the 14B then reads 5582 MiB at
   16k (2688 -> 1344 MiB KV) or 5663 MiB with q8_0 KV (2688 x 0.53, the scale tested at
   `Tests/XeonLLMTests.swift:554`), both under 6144 MiB. Trade-off: changes what the user asked
   for (window, cache precision) and needs a rule for which one gives first.
3. **Warn only.** The estimate already says `.slow`; show it next to the model and leave the
   launch alone. Trade-off: no behaviour change, the overcommit stays and the run depends on
   metal/0078.
4. **Hand the decision to the engine's `--fit`** (ticket 76). Trade-off: not available while the
   app passes `-ngl 99`, and its answer on this card is unmeasured.

## Tests

`Estimator.prefersHostPlacement` cases live in `EstimatorTests`,
`Tests/XeonLLMTests.swift:358`, on the D700 fixture at `Tests/XeonLLMTests.swift:349-356`.
The case next to the rule is `testThe14BFitsAcrossBothCardsAndStaysOnThem`,
`Tests/XeonLLMTests.swift:583-589`; it asserts `.card` for the 14B on `multiGPU: true` at the
default 16k. A new case for 14B at 32k belongs beside it.

## Done when

- A test for the 14B (8.38 GiB, 14.8B, 40 layers) at `ctx: 32768` on `d700HW` with
  `multiGPU: true` asserts the placement the chosen option asks for.
- The 14B layer split at the app's launch reads under `6144` MiB per card in a server log:
  the memory breakdown table `model + context + compute` against `total`
  (`vendor/llama.cpp/common/fit.cpp:922-926`; printed at shutdown by
  `vendor/llama.cpp/tools/server/server.cpp:931`). Load, stop the server, read the table.

## Comments
