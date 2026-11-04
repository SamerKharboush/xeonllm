# 01: the DFlash drafter on the idle card for the expert tier

Status: resolved (measured: does not pay; app change not shipped)
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

### 2026-11-04: answer (orchestrator)

**The drafter on the idle card runs, but it does not pay.** The app change is not shipped. It
is kept as `evidence/01/app-drafter-on-idle-card.diff`, with six `ServerSettings` tests, for when
ticket 04 changes the verify cost.

Mocca's two attempts were rejected:
- The first left the planner counting all 26.6 GiB of the target on the drafter's card, so the
  drafter stayed off. Its "other card" set was empty with both cards selected, it overrode a
  picked card, it added no tests, and it reported test failures that do not exist.
- The second recursed forever (`expertTierCards` -> `dflashSelection` -> `dflashMemoryPlan` ->
  `expertTierCards`). It dropped `GGML_METAL_DEVICE_INDEX` from the expert tier when no drafter
  was present, passed `-devd 1`, which names no device, and still had no tests. The
  orchestrator wrote the change.

**The engine question.** `--split-mode none -mg 0` keeps the target on the first listed card
(`src/llama.cpp:339-351`, `llama_prepare_model_devices`; Dynamic MoE's probe builds its model
params from the same flags, `common/tosh-plan.cpp:320`). The run confirms it: the memory table
shows the target on one card only.

**An engine bug found and fixed.** The first real launch aborted:

    ggml-backend.cpp:1127: pre-allocated tensor (output.weight) in a buffer (MTL0_Private) that
    cannot run the operation

The drafter borrows the target's output head. `spec/0073` copied it to the drafter's card only
from host memory, but on the expert tier the head sits in the other card's private memory. The
patch now copies it from another card too, with `ggml_backend_tensor_copy`:

    dflash lm head copied from MTL0_Private to MTL1_Private (397.9 MiB, q6_K)

The series applies 88/88 at `d81235049`. The host path is unchanged.

**The A/B.** Method:
- dev engine `build-static` (`d81235049` + 88 patches with the new 0073, AVX1, 0 AVX2/FMA);
- Ornith-1.0-35B Q6_K, the launch the rebuilt app logged: `-c 32768 -t 12 -fa 1 --dynamic-moe on`,
  expert tier on card 1;
- with the drafter: `GGML_METAL_DEVICE_LIST=1,0`, `-md <Qwen3.6-35B-A3B-DFlash Q8_0> --spec-type
  draft-dflash -ngld 7 -ctkd q8_0 -ctvd q8_0 --split-mode none -mg 0 -devd MTL1`;
- without it: beta.6's `GGML_METAL_DEVICE_INDEX=1`, no draft flags;
- 6 servers, alternating;
- each server: 4 requests of 128 tokens, temperature 0, `cache_prompt:false`, the first a warmup;
- display awake (IODisplayWrangler power state 4) throughout.

| server | mode | measured requests, tok/s | accepted / drafted |
|---|---|---|---|
| 1 | no drafter | 14.904, 14.956, 14.951 | — |
| 2 | drafter | 15.227, 14.316, 13.654 | 62/81, 44/60, 36/54 |
| 3 | no drafter | 15.433, 15.433, 15.402 | — |
| 4 | drafter | 13.880, 14.539, 14.534 | 34/54, 42/60, 42/60 |
| 5 | no drafter | 15.419, 15.423, 15.400 | — |
| 6 | drafter | 14.181, 14.098, 14.164 | 36/54, 36/54, 36/54 |

Without the drafter the measured requests span 14.90-15.43 tok/s; with it, 13.65-15.23. Two of
the three drafter servers are below every no-drafter request. Acceptance falls after the warmup.

**Text.** Byte identity cannot gate this pair: the expert tier's own text is not deterministic.
Server 1, without a drafter, gave two texts across its requests (they first differ at "I should" /
"I'll"). Dynamic MoE's cache moves experts between the CPU and the card from one request to the
next, which changes the order of the sums. Both texts occur with and without the drafter. One
drafter warmup gave a third text; it first differs at character 257.

**Why it does not pay** (a mechanism, not measured here): to verify k drafted tokens the target
runs its CPU experts over k rows, and on this AVX1 CPU that costs about k single tokens (the
`core/0022` multi-row dots are AVX2-only). Ticket 04 is the lever. Re-run this A/B after it, from
the saved diff.

Evidence: `evidence/01/` (ab.sh, ab.tsv, ab.args, per-request JSON and text, server logs, the
crash log, the memory table from the `-lv 4` run).
