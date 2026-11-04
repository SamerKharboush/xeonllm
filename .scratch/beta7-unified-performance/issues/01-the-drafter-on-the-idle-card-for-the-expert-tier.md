# 01: the DFlash drafter on the idle card for the expert tier

Status: ready-for-agent
Type: task
Spec: `../spec.md` (user stories 1-7)

## Problem

beta.6 launches Ornith-1.0-35B Q6_K on the expert tier: Dynamic MoE on one card (card 1, the one
with the most free VRAM), with the experts it cannot hold computed on the CPU. The other card does
nothing.

The DFlash drafter for this model is on disk (`<stem>.dflash.gguf`, 421 MB Q8_0). The app turns it
off. The beta.6 log line is:

    dflash : off by memory planner (need 30.99 GiB, budget 10.5 GiB)

There are two causes, both in the app:
- **The drafter's memory plan models expert placement only through `--n-cpu-moe`.** The expert
  tier launches with `--dynamic-moe on` and no `--n-cpu-moe`, so the plan counts the whole
  26.6 GiB file as resident on the card. It also budgets against every selected card together,
  not against the card the drafter would use.
- **The draft gate refuses DFlash whenever the auto-plan is on and the plan is not `full_gpu`.**
  That always holds on the expert tier.

Evidence that the hardware can do it: on 2026-10-31 the same 35B ran at `-ngl 0` with the
drafter on card 1 (`-devd MTL0`). The text was byte-identical to plain decoding
(`.scratch/firellama-maxperf/evidence/the-drafter-head-on-the-card-2026-10-31.md`).

## What to build

On the expert tier, when the model has a DFlash drafter and DFlash is not off for it:

1. **Visibility.** The engine sees both cards, with the expert tier's card first, so that Dynamic
   MoE keeps planning on that card and the drafter runs on the other (`-devd` naming the second
   visible device).
2. **The drafter's plan budgets the other card alone:**
   - that card's VRAM, less the reserve;
   - the drafter's weights per offloaded layer, its q8_0 KV at the launch context, and the fixed
     DFlash compute (1.9 GiB);
   - none of the target's weights or KV.
3. **The gate.** The draft gate allows DFlash on the expert tier when that plan gives
   `gpuLayers != nil`. Otherwise it stays off, with the planner's reason in the banner.
4. **The banner** names the drafter's card: e.g. `dflash : auto, ngld=N on card 0 (other card;
   estimated X / Y GiB)`.
5. **A user choice wins:**
   - DFlash off for the model, or a picked card (`gpuIndex >= 0`), keeps beta.6 behaviour: no
     drafter on another card.
   - With only one card present, beta.6 behaviour.

**Open engine question, settle it first from the source.** With two Metal devices visible and
`--dynamic-moe on`, does the pinned engine's plan (`vendor/llama.cpp/common/tosh-plan.cpp`, the
multi-device code around `read_vram_per_device` and the `n_dev >= 2` block) place target weights
or KV on the second device?
- If it can, find the flags that keep the target on device 0 only: for example `--split-mode
  none` with `-mg 0`, or `--tensor-split 1,0`. Cite the file:line that proves it.
- If no flag combination provably keeps the target on one device, **stop**. Make no launch change
  and report what you found.

Also read upstream #31506 (`2cbca389f`, "dflash: copy hidden features via device copies") if it is
in `vendor/llama.cpp`'s history or `patches/`. Report whether the pin's DFlash already copies the
target's hidden features across devices.

## Seam and tests

- **The seam is `ServerSettings`**, the same as `ServerSettingsTests`: a sparse model file with a
  minimal MoE GGUF header at the 35B's size, `d700HW`, `multiGPU = true`, and a DFlash drafter
  file beside it.
- **Assert on `resolvePlacement`, `arguments` and `environment`:**
  - a two-card D700 box with a 35B-sized MoE model and a drafter → expert tier; both cards
    visible with the expert card first; `-md <drafter> --spec-type draft-dflash -ngld N -devd
    <the second device>`; no flag that splits the target;
  - DFlash set off for the model → no `-md`, beta.6 environment;
  - a picked card → no `-md` on another card;
  - the other card too small (a hardware fixture with a small second card) → no `-md`, and the
    reason is available for the banner;
  - one card only → beta.6 behaviour.
- **A planner test:** the expert-tier plan for the 35B drafter does not include the target's
  weights, and fits a 6144 MiB card at `ctx` 32768.
- `DflashMemoryPlanner` and the GPU list come from code the tests can feed. If a test needs a
  hardware fixture, follow how `d700HW` and `expertTierCard` tests do it. Add no new global state.

## Must not

- Run any model, `llama-server`, `llama-bench`, the app or `scripts/stress-release.sh`. GPU gates
  are run by the orchestrator. Card 0 drives the display, and an overcommitted card panics this
  Mac.
- Change engine sources or `patches/`.
- Change placement for any model that is not on the expert tier.
- Commit, tag, push, or touch `dist/`.

## Gates (implementer)

- `swift build` and `swift test` from the repo root.
  - Baseline: 520 tests, 16 skipped, and failures only in the
    `MCPStdioTransportTests.testAnswersRacingTheirDeadlinesResolveEachRequestOnce` race.
  - Paste the summary lines.
- `swift test --filter` the new tests, and paste the summary line.

## Gate (orchestrator, after review)

The launch:
- Ornith-1.0-35B Q6_K at the app's launch (`-c 32768 --dynamic-moe on`, expert tier on card 1),
  through the test app `dev.xeonllm.gatetest`;
- the model given by a real path or a hard link, never a symlink.

Read the banner and the engine log first:
- `dflash` is enabled with an `ngld`;
- there are per-device buffers on both cards;
- card 0's total stays under its working set.

Then the A/B:
- 6 alternating servers, drafter against no drafter;
- each server: 1 warmup and 3 measured requests, 128 tokens, greedy, the BST prompt;
- report decode tok/s, accepted/drafted and draft ms per request;
- the text must be byte-identical with and without the drafter;
- record whether the display was awake (ticket 72).

Method line:
- the engine sha, `d81235049` plus 88 patches;
- the model and quant;
- `-c` and `-t`;
- each card's role;
- N, and whether the warmups were discarded.

Ship only if the text is identical and the run is clean (no watchdog, no exit). Report the speed
either way, as two observations, with no ratio against a modelled figure.

## Comments
