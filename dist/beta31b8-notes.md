# XeonLLM 0.87.31-beta.8 (no-AVX2, AVX1 engine)

A fork of [ToshLLM](https://github.com/engeldlgado/toshllm) by Engelbert Delgado, maintained
by Samer Kharboush at <https://github.com/SamerKharboush/xeonllm>. Upstream ToshLLM 0.87.31
with this fork's FirePro D700 work on top. Built and measured on a Mac Pro 6,1: Xeon E5-2697
v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

This beta makes deep prompts on the D700s faster, lets a model that sits in RAM read its prompt
on a card, fixes a dense model split over both cards and RAM that answered zeros, makes the
app's "AMD flash attention" switch actually turn it off, and closes the DFlash tool-call ticket
from beta.7. It is gated by `specs/release-contract.md` on its shipped binaries and on the app's
own launch of each model.

## Install

Drag XeonLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is ad-hoc signed, not notarized: right-click it once and choose **Open**. **In-app updates
are off**, because the updater reads upstream's releases. Settings, conversations and Keychain
items carry over from beta.7.

## Faster deep prompts on the D700s

On a 64-lane card, prompt attention for head size 64 and 128 now runs as a mat-mul, a softmax and
a mat-mul (`metal/0083`) instead of the flash-attention kernel, which slows down sharply as the
cached context grows. `llama-bench -fa 1 -ub 128 -p 512` at a cached depth of 6144 tokens,
Qwen3-4B Q4_K_M, card 1, dev build of this engine (`build-fa`, series through 0084), one process
per side, `-r 1`: 56.36 tok/s, against 27.61 with the old route (`TOSH_FA_PF_W64=1`). At depths 0,
2048 and 6144, three processes per side: 92.9 / 76.5 / 56.1 against 88.0 / 51.9 / 27.6 tok/s.
Decode is unchanged within noise and the generated text is byte-identical.

The decomposed route keeps a full score matrix, so it is capped at 256 MiB per attention node
(`metal/0085`); above that the flash-attention kernel runs. Without the cap a Qwen3-14B Q4_K_M
split by layer over both cards at `-c 32768` decoded at 0.49 tok/s after a ~5.4k-token prompt;
with it 3.39-3.41, the same as the old route. `TOSH_FA_PF_DECOMP_MAX_MB` changes the cap.
**Known limit:** on that launch at the engine's default `-ub 512` the prompt reads at 12.6 tok/s
against 17.1 with `TOSH_FA_PF_W64=1`; at the app's own `-ub 128` it reads 22.6 against 21.4-21.8.
If you run the engine by hand at `-ub 512` on deep prompts, `TOSH_FA_PF_W64=1` restores the old
route.

## A model in RAM reads its prompt on a card

When a model's weights stay in RAM (`-ngl 0`, or the app's host placement), large prompt
mat-muls now run on a D700 from copies of those weights (`core/0082`). Before, the engine never
did this on a Mac with Accelerate, because it looked only at the last backend. A size check
keeps it off when the card's compute buffer would pass 1536 MiB (`TOSH_OFFLOAD_MAX_COMPUTE_MB`);
the server log says `op offload on:` or `op offload off:` with the size. Qwen3-0.6B Q8_0 at
`-ngl 0 -c 4096`: prompt 198.2 tok/s with it, 180.9 with `--no-op-offload` (dev build of this
engine with `core/0082` last, N=1 each, the server's own rate; not a benchmark). The app's server log header names the card a host-placed dense model uses
(`prompt offload: card <i>`).

MoE experts stay on the host (`core/0086`): with both cards visible, the 35B at `-ngl 0` aborted
at a 2048-token prompt once expert mat-muls could move (`GGML_ASSERT id < n_expert`; the cause is
not isolated). `TOSH_OFFLOAD_MOE=1` allows it again; the app gives a host-placed MoE
`--no-op-offload` anyway.

## Fixed

- **A dense model split over both cards and RAM answered "0000..."** (`metal/0084`): the fused
  gated-delta-net state kernel is now off when a model spans several cards. The dense qwen35 27B
  Q6_K with `GGML_METAL_DEVICE_LIST=0,1 -ngl 12 --split-mode layer` answers the same text as on
  one card; `TOSH_GDN_STATE_FUSION_MULTI=1` brings the zeros back. One card keeps the fused kernel.
- **Turning "AMD flash attention" off in the app did nothing**: the engine only reads
  `TOSH_FA_AMD_DISABLE`. The app now sets it when the switch is off.
- **The 35B with the DFlash drafter lost the tool call** (beta.7 ticket 20): it makes the call
  in both modes in this beta's stress run, with draft acceptance 0.79-0.83.

## Text that moved since beta.7

Greedy text on the cards is byte-identical to beta.7 for every model in the stress set. On the
host (`-ngl 0`) some answers differ from beta.7 after a few to a few hundred characters. Two
intended route changes cause it, and each has an off switch that brings back beta.7's text:

- Qwen3 0.6B, 4B Q4_K_M, 4B Q6_K, 8B and 14B: `metal/0083`'s route decision is also taken for a
  host run, so prompt attention on the CPU now uses flash attention. `TOSH_FA_PF_W64=1`
  restores beta.7's text.
- Ternary-Bonsai-2-27B PQ2_0: `core/0082` runs its prompt mat-muls on a card. `--no-op-offload`
  restores beta.7's text; the 1528-token prompt request took 236.0 s with offload and 414.1 s
  without (N=1 each, wall time including 64 generated tokens).

The 35B with dynamic MoE answers differently from run to run in every mode, in beta.7 as well:
which experts sit on a card depends on free card memory at load, and card 0 shares its memory
with the display.

## Stress test (contract section 4)

Each model was launched by the rebuilt app itself, a copy under the test id
`dev.xeonllm.gatetest`, and the engine was driven with that launch: prompts of 16 to 8300 words,
a six-turn conversation, a context-filling prompt and a request after it, an over-context prompt
(HTTP 400) and a request after it, a tool call, a cancelled stream and a request after it.

| model | tensor (the app's flags) | layer | `-ngl 0` |
|---|---|---|---|
| Qwen3-0.6B Q8_0 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q4_K_M | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q6_K | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-8B Q4_K_M | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| LFM3-1.7B F16 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-14B Q4_K_M (ctx 16384 by the app's fit) | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Nemotron-3.5-Bolt-E4B Q4_K_M (drafter on by the app) | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Ternary-Bonsai-2-27B PQ2_0 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Ornith-1.0-35B Q6_K (dynamic MoE) | 20 pass, 1 skip | with the drafter: 20 pass, 1 skip | — |

- The skip is two parallel requests: the app launches `--parallel 1`.
- Layer and tensor text is byte-identical on every model that ran both, and identical to beta.7
  on the cards.
- No panic, watchdog, gpuRestart, assert, `kernel not found` or `@@@@` answer during the run.

## Gates

- the patch series: 96 of 96 apply to `d81235049`;
- 0 AVX2/FMA instructions in every shipped Mach-O;
- `test-backend-ops` on each card: every op 13983/13983, `FLASH_ATTN_EXT` 1993/1993;
- kernel coverage on each card: 0 missing;
- prefill bands on the shipped engine: 20 of 20 rows, the PQ2 under tensor stops with its own
  exit code (86) as designed; the 35B at `-ngl 0` runs every band with 0 asserts;
- the 64-lane paths are on: `TOSH_MV_ROWS8_DISABLE` changes Qwen3-4B tg128 (16.71 -> 14.16);
- the preflight gate and `assert_artifact` pass (engine commit == pin, bundle `0.87.31-beta.8`);
- `scripts/test-engine.sh` on the shipped llama-server: 20 of 20;
- the `0078` repro (Qwen3-14B layer split over both cards, `-c 32768`, ~5.4k-token prompt):
  HTTP 200, answer text checked (not `@@@@`), decode 292.76 ms per token;
- `swift test`: 541 tests, 16 skipped, the only failure the pre-existing `MCPStdioTransportTests` race;
APPGATES

DMG sha256: `ad679f5cb2341067af43ef960bbd064874a899b6c87b65de2ec64c0d3750a62b`.

## Not covered

- **Qwen3-14B split by layer over both cards at `-c 32768` sometimes answered "@@@@"** (ticket
  24): 3 of 40 recorded runs, with beta.7's engine too, none in 22 strictly serial runs. That
  launch overcommits each card; the app never makes it (it lowers the 14B to 16384). The repro
  gate now fails on such an answer.
- **The decomposed prompt route at `-ub 512` on deep prompts** is slower than the old route (see
  above); the app launches `-ub 128`.
- **Two parallel requests** were not tested, because the app launches `--parallel 1`.
- **A 32-lane GPU:** there is none here. The D700 rules sit inside `simd_width == 64` checks.
- **The real chat went through the engine's API, not the chat window.**
- The tag is annotated, not signed.
