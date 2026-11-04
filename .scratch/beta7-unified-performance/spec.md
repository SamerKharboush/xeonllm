# Spec: use the whole box (12-core AVX1 Xeon, 64 GB, two D700s) for bigger and faster models

Status: ready-for-agent
Source: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` (primary-source survey),
`dist/beta31b6-notes.md` ("Not covered").

## Problem Statement

The owner runs XeonLLM on a Mac Pro 6,1. Its parts:
- a 12-core Xeon E5-2697 v2 with AVX but no AVX2 or FMA;
- 64 GB of RAM;
- two 6 GB FirePro D700 cards with no link between them.

beta.6 now loads and chats on every supported model. But it is "not way better than the
original", and a long "Not covered" list remains. On the 35B MoE model one card sits idle. Models
too big for the cards prefill slowly on the CPU. One of the fork's own CPU speedups never runs on
this CPU. LFM3 models do not load. A dense model split across both cards and RAM answers with
zeros.

The owner has seen faster engines online and wants their ideas here. The survey found that every
external engine with a faster CPU path needs AVX2 or better, and those that use the GPU need CUDA,
ROCm or Apple Silicon. Importing an engine is not an option. The gains must come from this
engine and app.

## Solution

Six steps, in order. Each one ends with a measurement on this machine that follows the
CLAUDE.md performance rules.

1. **Put the DFlash drafter on the card the expert tier leaves idle.** This makes the 35B use
   both cards, RAM and the CPU together.
2. **Measure what a D700 can actually read**, compare mat-vec kernel speed across the quant
   types, and only then change the GCN mat-vec layout.
3. **Let a model placed on the host use a card for prefill**, after measuring the PCIe copy
   rate.
4. **Give the AVX1 CPU the multi-row dot kernels** the fork has only for AVX2. Measure the cost
   of verifying k tokens at once first.
5. **Backport LFM3 support** from upstream.
6. **Fix the zeros** on a dense model split across both cards and the host (ticket 68), so a dense
   model can use both cards plus RAM.

From the owner's side: the 35B gets a drafter, big dense models prefill faster, LFM3 loads, and a
dense model larger than both cards can use both cards and RAM at once. Every change ships only
with a method line and a gate result, and the notes say what was not measured.

## User Stories

1. As the owner, I want the 35B MoE model to use the second D700 for its drafter, so that no card
   sits idle while I chat.
2. As the owner, I want the drafter to make no difference to the text, so that speed does not
   cost me quality.
3. As the owner, I want the log header to say where the drafter runs and why, so that I can see
   the placement without reading the code.
4. As the owner, I want the drafter turned off with a stated reason whenever it would not fit the
   other card, so that a launch never overcommits a card.
5. As the owner, I want the app never to place the drafter so that card 0, the display card, gets
   more than its working set, so that the Mac never panics.
6. As the owner, I want the drafter's speed reported against no drafter in the same session, so
   that I know whether it pays on this machine.
7. As the owner, I want a choice I made myself (DFlash off, a picked card) respected on the
   expert tier, so that the automatic plan never overrides me.
8. As the owner, I want to know what one D700 can actually read per second, so that kernel work
   aims at a real target.
9. As the owner, I want the mat-vec speed of each quant type measured on the card, so that I can
   pick the quant that decodes fastest here.
10. As the owner, I want the per-op decode table re-taken on beta.6, so that the next kernel
    change targets the op that costs the most today.
11. As the owner, I want a GCN-specific weight layout only when the measurements show room, so
    that no risky kernel ships for nothing.
12. As the owner, I want big dense models that run on the host to prefill on a card when that is
    faster, so that long prompts stop taking minutes.
13. As the owner, I want the PCIe copy rate measured, so that the prefill decision rests on a
    number from this machine.
14. As the owner, I want prefill offload proven to happen before its speed is compared, so that
    an inert switch is never reported as a result.
15. As the owner, I want the CPU kernels to share weight unpacking across several tokens on AVX1,
    so that drafting, prompt tails and parallel slots run faster on the host.
16. As the owner, I want the CPU change to produce bit-identical results, so that answers do not
    change.
17. As the owner, I want the built binaries to keep 0 AVX2/FMA instructions, so that the app never
    crashes on my CPU.
18. As the owner, I want the cost of verifying k tokens measured on the host, so that I know which
    speculative methods can ever pay here.
19. As the owner, I want LFM3 models to load and pass the stress cells, so that the "unknown
    architecture" line leaves the notes.
20. As the owner, I want a dense model larger than both cards to run across both cards and RAM
    with correct text, so that I can run bigger dense models than the cards alone hold.
21. As the owner, I want every speed figure to carry a method line and no ratio against a modelled
    ideal, so that the release notes stay honest.
22. As the owner, I want each step to be a separate ticket with its own gate, so that a failure in
    one step does not block the others.
23. As a delegated implementer, I want each ticket to state the files it touches, the seam its
    tests use, and what I must not run, so that I can work without the chat history.
24. As the orchestrator, I want every change re-gated on the shipped binaries before a release,
    so that the release contract still holds.

## Implementation Decisions

- **No external engine is imported.** The survey checked the blockers in their source:
  ik_llama's IQK path needs `__AVX2__`; KTransformers needs AMX/AVX-512; T-MAC and BitNet.cpp
  have no AVX1 path; vLLM, SGLang, TensorRT-LLM and ExLlama need CUDA or ROCm; MLX needs Apple
  Silicon. The ideas are re-implemented in this fork's patch series and app.
- **Keep the fork's Dynamic MoE over upstream's `--moe-cache-mib`.** Upstream's expert cache
  uploads every miss over PCIe and synchronises at every MoE layer, and it refuses tensor split.
  Dynamic MoE computes misses on the CPU. Two upstream pieces may be taken later:
  `MUL_MAT_ID` index −1 skipping (#26631) and the batched tensor copy API (#30881).
- **The drafter on the expert tier (ticket 01) is an app change first.**
  - The drafter's memory plan must stop treating the expert tier's experts as resident on the
    drafter's card. The drafter is budgeted against the card the expert tier does not use, and
    against that card alone.
  - The draft gate must allow DFlash on the expert tier when that plan fits.
  - The engine must see both cards, with the expert tier's card first, so that Dynamic MoE still
    plans one card while the drafter is pinned to the other with `-devd`. Whether the pinned
    engine's plan stays on one card when two are visible is an open engine question. The ticket
    settles it from the source, with citations, before changing the launch. If the plan would
    spread over both cards, the ticket stops and reports.
  - The same placement rules as beta.6 apply: never more than a card's working set, card 0 is the
    display card, and links are sized by their target.
- **Card measurements (ticket 02) come before any kernel layout change.** A repacked GCN buffer
  type is decided only from the measured read ceiling and the type sweep.
- **Host prefill on a card (ticket 03) changes host placement only if it is measured to pay.**
  Host placement then keeps one card visible for op offload.
- **The AVX1 multi-row dots (ticket 04)** use 128-bit integer code (SSSE3/SSE4.1) with AVX for
  float accumulation, the same split as the pin's own AVX1 `vec_dot` paths. Results must be
  bit-identical to repeated single-row calls.
- **The LFM3 backport (ticket 05)** applies upstream's LFM base change, then the LFM3 text model,
  as one new model patch. The tensor-split follow-up is optional.
- **Ticket 68** stays the bug ticket for the zeros. Ticket 06 here tracks it as the blocker for
  using both cards plus RAM on one dense model.

## Testing Decisions

- **A good test checks external behaviour:** the launch the app builds (its arguments and
  environment), the text the engine returns, the op results `test-backend-ops` compares. It does
  not check internal helpers.
- **The seam for every app ticket is `ServerSettings`.** A test configures settings with a model
  file and hardware, and asserts on `resolvePlacement`, `arguments` and `environment`, plus the
  log banner line where one exists. This is the seam used by the existing placement and context
  fit tests. Prior art: `ServerSettingsTests` (sparse model files with a minimal MoE GGUF header,
  `d700HW`), `EstimatorTests` (context fit), `SymlinkedModelSizeTests`.
- **The seam for every engine ticket is the shipped binary:**
  - `test-backend-ops` on each card, 0 failures;
  - `llama-bench` and `llama-server` cells with a method line;
  - the release contract's stress cells for anything that changes a launch.
- **A differential measurement first proves its control takes effect** (CLAUDE.md rule 2): a log
  line, GPU activity, or a changed dispatch.
- **Every throughput figure carries a method line:**
  - engine sha and pin, model and quant;
  - ctx, batch and threads;
  - card;
  - N, and whether warmups were discarded.
- **No model runs from a delegated implementer.** GPU runs are the orchestrator's, after the
  one-card and both-card size guards in `scripts/stress-release.sh`.

## Out of Scope

- Importing any external engine, or a CUDA/ROCm/HIP/Vulkan backend.
- A tensor split of the PQ2_0 27B (the engine refuses it by design; the layer split serves it).
- A 32-lane GPU test (no such hardware here).
- Shipping `--parallel 2` (a stress cell may test it; the app keeps `--parallel 1`).
- Signing the tag (needs the owner's key).
- UI automation of the chat window.
- A drafter for host placement: the 10-31 evidence covers it, but no host-placed dense model on
  disk has a DFlash drafter. Revisit after ticket 03.

## Further Notes

- **"Bigger" is fast only for MoE models.** A dense model read from host RAM is bounded by
  51.6 GB/s divided by its bytes per token. That 51.6 GB/s is the measured read ceiling of the
  host, so a 40 GB dense model cannot pass about 1.3 tok/s on this host.
- Upstream changes worth reading before ticket 01: #31506 (`2cbca389f`, DFlash hidden features
  via device copies).
- Card 0 has a recorded slow mode while the display is awake (ticket 72). Gates record the display
  state.

## Tickets

- `issues/01-the-drafter-on-the-idle-card-for-the-expert-tier.md` (ready-for-agent)
- `issues/02-measure-the-card-read-ceiling-and-the-mat-vec-type-sweep.md` (ready-for-human)
- `issues/03-prefill-host-placed-dense-models-on-a-card.md` (ready-for-human)
- `issues/04-avx1-multi-row-cpu-dots.md` (ready-for-agent, blocked by its step 0 measurement)
- `issues/05-backport-lfm3.md` (ready-for-agent)
- `issues/06-a-dense-model-across-both-cards-and-ram.md` (needs-triage, tracks ticket 68)
