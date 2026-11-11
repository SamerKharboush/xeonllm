# XeonLLM 0.87.31-beta.7 (no-AVX2, AVX1 engine)

A fork of [ToshLLM](https://github.com/engeldlgado/toshllm) by Engelbert Delgado, maintained
by Samer Kharboush at <https://github.com/SamerKharboush/xeonllm>. Upstream ToshLLM 0.87.31
with this fork's FirePro D700 work on top. Built and measured on a Mac Pro 6,1: Xeon E5-2697
v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

This beta fixes a way a long prompt could panic the Mac, loads LFM3, leaves out a card that has
started computing wrong answers, refuses to start when another program holds the engine's port,
and lets MoE models on the host use the Xeon's AVX1 for their expert mat-muls. It is gated by
`specs/release-contract.md` on its shipped binaries and on the app's own launch of each model.

## Install

Drag XeonLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is ad-hoc signed, not notarized: right-click it once and choose **Open**. **In-app updates
are off**, because the updater reads upstream's releases. Settings, conversations and Keychain
items carry over from beta.6.

## A long prompt could panic the Mac

On 2026-11-07 the app's launch of Qwen3-14B Q4_K_M, split by layer over both D700s at a 16384
context, read an ~8300-token prompt on top of ~5500 cached tokens. Each prompt batch's command
buffers ran for seconds on card 0, the card that drives the display; WindowServer stopped
answering for 120 s and macOS panicked. The GPU time of a prompt batch grows with the cached
context: one 512-token batch of a 4B on one D700 costs 6.2 s at an empty context and 17.7 s at
6k. beta.6 had the same exposure; its stress run happened not to reach it. Two changes:

- **The engine bounds each batch command buffer by its measured GPU time** (`metal/0081`). It
  times every buffer of a prompt batch, predicts the next batch from that, and cuts it into as
  many buffers as keep each near 50 ms, up to 64 (an unmeasured first batch takes 64).
  `TOSH_MTL_CB_TARGET_MS` sets the target (0 restores the old layout); `TOSH_MTL_CB_STATS=1`
  logs every batch.
- **A dense model on a card reads its prompt in 128-token batches**, so the heaviest single
  operation (attention at depth) stays short too.

Measured on the shipped `llama-server`, `TOSH_FA_AMD=1`, `TOSH_MTL_CB_STATS=1`, one request each:

| launch | longest command buffer | prompt t/s | timeouts |
|---|---|---|---|
| Qwen3-4B Q4_K_M, card 1, `-c 8192`, ~6000-token prompt, old layout (`TOSH_MTL_CB_TARGET_MS=0`, ub 512) | 4303.4 ms | 42.5 | 0 |
| the same, shipped (bound on, ub 128) | 126.6 ms | 43.1 | 0 |
| Qwen3-14B Q4_K_M, layer split over both cards, `-c 16384`, ub 128, ~4k-token prompt | 172.7 ms | 28.8 | 0 |
| the same, ~8k-token prompt | 250.1 ms | 22.9 | 0 |
| the same, ~13k-token prompt | 349.9 ms | 18.1 | 0 |

The generated text of the two 4B rows is byte-identical. Prompt rates are the server's own
`prompt_per_second` for one request (N=1); they are not benchmarks. The 128-token batch costs
no prompt rate on a short prompt: `llama-bench -p 512 -fa 1 -r 3`, Qwen3-4B Q4_K_M, card 1, two
processes per side, dev build of the same engine: ub 128 88.06 ± 0.06 and 87.98 ± 0.14, ub 512
83.00 ± 0.19 and 82.50 ± 0.03 tok/s. At 13k cached tokens the 14B still has a 350 ms buffer: the
64-buffer cap and one attention node set that floor.

## Added

- **LFM3 models load** (`model/0079`, a backport of upstream's shared LFM base and the LFM3 text
  model). LFM3-1.7B F16 answers "The capital of France is Paris." on card 0, on card 1 and on the
  host, byte-identical. On each card, `llama-bench -p 512 -n 128 -r 5 -fa 1`: pp512 230.3-230.4
  and tg128 23.01-23.03 tok/s (dev build of this engine). The engine cannot tensor-split LFM3;
  the app now falls back to a layer split for every architecture the engine refuses to tensor-split.
- **A card check at launch.** Each discrete card runs a short known-answer test. A card that
  answers wrong is left out of the run and named in a banner; if every card fails, nothing is
  left out. On 2026-11-04 one D700 returned wrong results after a run of GPU resets, and every
  answer split across it was garbage until a cold power-off.
- **AVX1 multi-row expert dots** (`core/0080`): when several tokens of a batch go to the same
  expert, Q6_K, Q4_K and Q8_0 weight blocks are unpacked once for all of them. Results are
  bit-identical to the single-row dots (36 test cases), and a MoE run prints
  `ggml_cpu: multi-row dot ON for <type> (AVX1)`; `GGML_CPU_NO_MULTI_DOT=1` turns it off. The
  measured effect on the 35B is small: no change resolved at up to 4 tokens per verify; at 8 the
  processes with it took 589 and 612 ms per verify against 656 and 670 ms without (sd 14-45 ms,
  two processes per side).

## Fixed

- **Another program on the engine's port took the chat.** The app now checks the port before
  launch, names what holds it (command and pid) and refuses to start with a message.
- **A DFlash drafter on another card aborted at load** when the target's output head sat in a
  different card's memory (`spec/0073` now copies it from another device too).

## Changed

- The app icon is yellow.

## Stress test (contract section 4)

Each model was launched by the rebuilt app itself, a copy under the test id
`dev.xeonllm.gatetest` (saved settings: ctx 32768, f16 cache, tensor split over both cards), and
the engine was driven with that launch: prompts of 16 to 8300 words, a six-turn conversation, a
context-filling prompt and a request after it, an over-context prompt (HTTP 400) and a request
after it, a tool call, a cancelled stream and a request after it.

| model | tensor (the app's flags) | layer | `-ngl 0` |
|---|---|---|---|
| Qwen3-0.6B Q8_0 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q4_K_M | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q6_K | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-8B Q4_K_M | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-14B Q4_K_M (ctx 16384 by the app's fit) | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Nemotron-3.5-Bolt-E4B Q4_K_M | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| LFM3-1.7B F16 | not loadable before the fallback (below) | 20 pass, 1 skip | (ran with the tensor flag, not loadable) |
| Ternary-Bonsai-2-27B PQ2_0 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Ornith-1.0-35B Q6_K (expert tier) | 20 pass, 1 skip | drafter forced on: 19 pass, 1 skip, 1 fail (tools) | — |

- The skip is two parallel requests: the app launches `--parallel 1`.
- **Layer and tensor text is byte-identical** on every model that ran both (16-, 300- and
  1100-word prompts, greedy).
- **No panic, watchdog, gpuRestart, assert or timeout** during the run. The 14B layer split
  passed every band, including the 8300-word prompt on a deep cache that panicked the Mac on
  2026-11-07 with beta.6's engine.
- The LFM3 tensor-split fallback landed after this run (an app change only; the engine is
  unchanged); its unit tests are part of `swift test` under Gates.

## Gates

- the patch series: 91 of 91 apply to `d81235049`;
- 0 AVX2/FMA instructions in `llama-server`, `llama-bench`, `llama-perplexity` and
  `test-backend-ops`;
- `test-backend-ops` on each card: every op 13983/13983, `FLASH_ATTN_EXT` with
  `TOSH_FA_AMD=1` 1993/1993;
- kernel coverage on each card: 0 missing;
- prefill bands on the shipped engine: every model that fits one card passed on card 0 and
  card 1; the 14B, Nemotron, the PQ2 (layer) and Underdog 27B passed on both cards in layer and
  tensor; the 35B passed on the host; the PQ2 under tensor stops with its own exit code (86) as
  designed;
- the 64-lane paths are on, on both cards; `TOSH_MV_ROWS8_DISABLE` changes tg128 (Qwen3-4B
  16.71 -> 14.16, Nemotron 13.83 -> 12.04) and `TOSH_FULL_TG_DISABLE` changes Nemotron tg128
  (13.83 -> 13.61), card 1, so both rules are in the binary;
- the preflight gate: `-ngl 0` and `-ngl 99` each served 32 tokens, the forced-drop control
  reads 1; `assert_artifact`: engine commit == pin, bundle `0.87.31-beta.7` == VERSION;
- `scripts/test-engine.sh` on the shipped llama-server: passes (MCP cancel 20 of 20);
- the `0078` repro (Qwen3-14B layer split over both cards, `-c 32768`, one ~5.4k-token prompt):
  HTTP 200, no `kIOAccelCommandBufferCallbackErrorTimeout`;
- `swift test`: 541 tests, 16 skipped, failures only in the pre-existing `MCPStdioTransportTests` race;
- the mounted DMG: bundle id `dev.xeonllm.app`, version 0.87.31-beta.7, `TOSHNoAVX2` and `TOSHUpdatesDisabled` true,
  `codesign --verify --deep` passes, the bundled llama-server is the gated binary (sha256
  `1a68d3efcbf476e79b279425a2a367930439290abaa6a09629e96f828a12df90`);
- one real chat through the rebuilt app (test id, LFM3-1.7B F16 with the user setting "tensor split"):
  the app launched it with `--split-mode layer` and answered "The capital of France is Paris."
  at 22.2 tok/s.

DMG sha256: `d1a10b3dc782b46c9b39ee157b5431a482720d14b99c0378595663668520fae1`.

## Not covered

- **With the DFlash drafter forced on, the 35B does not make a tool call** (ticket 20): it
  writes 512 tokens instead, while the same request without the drafter makes the call. The
  app's own launch of the 35B leaves the drafter off (its planner needs 30.99 GiB against a
  10.5 GiB budget), so this needs a drafter forced on by hand. Workaround: turn the drafter off
  when using tools. To be fixed in beta 8.
- **The `0078` control** (`TOSH_MTL_PREFILL_CB=1`, which reproduces a GPU watchdog timeout on
  purpose) was not run: after two machine freezes this month no gate runs a command buffer long
  on purpose.
- **Two parallel requests** were not tested, because the app launches `--parallel 1`.
- **A 32-lane GPU:** there is none here. The D700 rules sit inside `simd_width == 64` checks.
- **The real chat went through the engine's API, not the chat window.**
- The tag is annotated, not signed.
