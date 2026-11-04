# XeonLLM 0.87.31-beta.6 (no-AVX2, AVX1 engine)

A fork of [ToshLLM](https://github.com/engeldlgado/toshllm) by Engelbert Delgado, maintained
by Samer Kharboush at <https://github.com/SamerKharboush/xeonllm>. Upstream ToshLLM 0.87.31
with this fork's FirePro D700 work on top. Built and measured on a Mac Pro 6,1: Xeon E5-2697
v2 (AVX, no AVX2/FMA), 64 GB, 2x FirePro D700, macOS 15.8.

beta.5 loaded every model and then failed in chat. This beta fixes each cause that was found.
It is the first release gated by `specs/release-contract.md`, on its shipped binaries and on the
app's own launch of each model.

## Install

Drag XeonLLM to Applications. **This build needs a CPU with AVX** (Sandy Bridge or later).
It is ad-hoc signed, not notarized: right-click it once and choose **Open**. **In-app updates
are off**, because the updater reads upstream's releases. Settings, conversations and Keychain
items carry over from beta.5; a ToshLLM folder that beta.5 skipped is merged once (below).

## Why chatting failed

- **Prompts of 448+ tokens crashed the engine on models with a BF16 tensor** (exit 11). The
  GEMM selector asked for `kernel_mul_mm_bf16e_f32_w_w64`, which the library never built. It now
  checks the library and falls back to a narrower kernel, and aborts with the kernel's name if
  none is left (`metal/0075`).
- **The 14B on both cards failed deep in a chat with "Compute error."** At the saved
  `-c 32768` with an f16 cache, Qwen3-14B Q4_K_M needs 6926 MiB per card against 6144 (3954
  weights + 2688 KV + 284 compute). The driver paged, a long prompt's command buffer ran past the
  macOS GPU watchdog (`kIOAccelCommandBufferCallbackErrorTimeout`), and every later request got
  HTTP 500. Two changes:
  - **A card launch lowers its context until the KV cache fits.** The 14B at a saved 32768
    launches at 16384; the log header says `context: 32768 -> 16384 (...)` and the server
    overview shows a note. The saved setting is not changed. Measured at 16384 on the
    bundled engine: 5613 MiB on card 0 and 5649 MiB on card 1 (model + context + compute, from
    the engine's memory table at shutdown). The 8B keeps 32768; Nemotron-3.5-Bolt-E4B launches
    at 31744. With a q8_0 cache the fit gives the 14B 30720 (the formula's figure; not launched).
  - **Batch graphs on a discrete card use shorter command buffers** (`metal/0078`): five
    instead of two. On the shipped engine the 14B repro at `-c 32768` answers (HTTP 200)
    where the control with `TOSH_MTL_PREFILL_CB=1` returns HTTP 500.
- **A model behind a symlink was sized as the link** (62 bytes). The placement rule read a
  28 GB model as 0 GB and put it on both cards whole; the driver paged GPU memory and macOS
  panicked. Every model and drafter size now follows links, and the model list shows a link
  to a model.

## Also fixed

- **Tool servers never started.** The engine and the MCP transport use the login shell's PATH
  plus the usual install locations. A server whose command is not found is named in the MCP
  settings.
- **The ToshLLM data was only half migrated.** When the XeonLLM folder already existed, the
  ToshLLM folder was skipped. It is now merged item by item, with XeonLLM's copy winning, and
  nothing of ToshLLM's is moved or changed.
- **The engine called itself "ToshLLM engine 0.87.31-beta.4".** It prints
  `XeonLLM engine <VERSION>`, and the build refuses a stale version stamp.
- **About and Donate** show Samer Kharboush and the XeonLLM repository; Donate opens the
  repository. ToshLLM stays credited as the upstream.
- **A remote MCP server over HTTPS failed with no explanation.** The web UI proxy says the
  engine has no HTTPS and names the way out (`server/0077`).
- Unary, binary and GLU kernels spread a row over threadgroups (`metal/0076`).

The llama.cpp series is 88 patches on `d81235049`.

## Measured

Method: the bundled engine (llama-bench sha256 `82725c76...`, llama.cpp `d81235049` plus 88
patches), card 1, `llama-bench -p 0 -n 128 -r 5 -fa 1`, one process per cell, llama-bench
discards its own warmup. A separate CPU-only `llama-server` (14B, `-ngl 0`, idle) was resident
during the run. Each cell is that process's mean of 5, with its sd. Each switch turns off one
patch, to show that it is in the binary.

| model | default tg128 t/s | `TOSH_MV_ROWS8_DISABLE=1` | `TOSH_FULL_TG_DISABLE=1` |
|---|---|---|---|
| Qwen3-4B Q4_K_M | 16.644 (sd 0.007) | 14.120 (sd 0.006) | 16.599 (sd 0.004) |
| Nemotron-3.5-Bolt-E4B Q4_K_M | 13.752 (sd 0.007) | 11.969 (sd 0.006) | 13.514 (sd 0.009) |

## Stress test (contract section 4)

Each model was launched by the rebuilt app itself: a copy of the bundle under a separate test
id, `dev.xeonllm.gatetest`, so the user's settings are not touched. The saved settings were
ctx 32768, an f16 cache and a tensor split over both cards. The cells:

- prompts of 16 to 8300 words;
- a six-turn conversation;
- a prompt that fills the context, then a request after it;
- a prompt over the context, which must be refused with HTTP 400, then a request after it;
- a tool call;
- a cancelled stream, then a request after it.

Modes:

- **app**: the flags the app logged;
- **layer**: the same with `--split-mode layer`;
- **cpu**: `-ngl 0`, three cells.

| model | the app's launch | app | layer | cpu |
|---|---|---|---|---|
| Qwen3-0.6B Q8_0 | both cards, tensor, ctx 32768 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q4_K_M | both cards, tensor, ctx 32768 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-4B Q6_K | both cards, tensor, ctx 32768 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-8B Q4_K_M | both cards, tensor, ctx 32768 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Nemotron-3.5-Bolt-E4B Q4_K_M | both cards, tensor, ctx 31744 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Qwen3-14B Q4_K_M | both cards, ctx 16384 | 20 pass, 1 skip (tensor) | 20 pass, 1 skip (see below) | — |
| Ternary-Bonsai-2-27B PQ2_0 | both cards, layer (below), ctx 32768 | 20 pass, 1 skip | 20 pass, 1 skip | 3 pass |
| Ornith-1.0-35B Q6_K | expert tier on card 1, ctx 32768 | 20 pass, 1 skip | — | 3 pass |

- The skip is two parallel requests: the app launches `--parallel 1`.
- **Layer and tensor text is byte-identical** on every model that ran both. The cells compared
  are the 16-, 300- and 1100-word prompts, greedy.
- **GPU and CPU text** match byte for byte on the 0.6B and the PQ2. On the other models they
  diverge partway through an answer. This is reported, not gated: the two backends sum in a
  different order.
- **There are no watchdog, assert or exit lines in any server log.**
- **The PQ2's context-filling prompt** (20,549 tokens) takes about 1145 s to prefill, which is
  past the script's 900 s per-request limit. It passes with a 2700 s limit, and the request
  after it is answered.
- **The 14B layer run:** its first pass sized the context-filling prompt for 32768 tokens.
  At 16384 it was refused with HTTP 400, which is correct. The resized prompt (15,168 tokens),
  the over-context refusal and the requests after each passed on a rerun.
- **The 35B passes the context-filling prompt** (20,507 tokens) in 214 s. Its decode is about
  13–14 tok/s. That rate is from the server log over 64 tokens and is not a benchmark.
- **A real chat:** the 14B through the test app's engine API, 200 tokens at 6.70 tok/s.

## Gates

- the patch series: 88 of 88 apply to `d81235049`;
- 0 AVX2/FMA instructions in `llama-server`, `llama-bench`, `llama-perplexity` and
  `test-backend-ops`;
- `test-backend-ops` on each card: every op 13983/13983, `FLASH_ATTN_EXT` with
  `TOSH_FA_AMD=1` 1993/1993;
- kernel coverage on each card (the engine's own check against the shipped metallib): 0
  missing;
- prefill bands on the shipped engine:
  - every model that fits one card passed on card 0 and on card 1;
  - the 14B, Nemotron, the PQ2 (layer) and Underdog 27B passed on both cards in layer and in
    tensor;
  - the 35B passed on the host;
  - the PQ2 under tensor stops with its own exit code (86, `RESHAPE cannot be tensor-split`),
    as designed;
- the 64-lane paths are on, on both cards: SIMD width 64, wave64 decode, aligned mat-vec reads;
- the preflight gate: `-ngl 0` and `-ngl 99` each served 32 tokens, and the forced-drop control
  reads 1;
- `assert_artifact` on the bundle: engine commit == pin, bundle `0.87.31-beta.6` == VERSION,
  llama-server sha256 `c854ada6695bcfa4aa7b11d82e480a5e615925f20e2d27e1e118813df86c53f5`;
- `scripts/test-engine.sh` on the shipped llama-server: 26 passed, 1 skipped, in each of five
  runs. One earlier gate run, on 2026-11-03, had one error in the `test_mcp_cancel` module: it
  ran 1 test instead of 20, so it failed while starting, not in a test case. It has not
  recurred.
- `swift test`: 520 tests, 16 skipped, 3 failures, all in the pre-existing
  `MCPStdioTransportTests` race;
- the mounted DMG:
  - bundle id `dev.xeonllm.app`, version 0.87.31-beta.6;
  - `TOSHNoAVX2` and `TOSHUpdatesDisabled` true;
  - `codesign --verify --deep` passes.

DMG sha256: `459af5340727abb063668bb1fbd7cc579d2e10dad19a24e95daa019747d98b0b`.

## Not covered

- **LFM3-1.7B does not load:** `unknown model architecture: 'lfm3'`. The pinned engine predates
  the architecture.
- **A tensor split of Ternary-Bonsai-2-27B PQ2_0 cannot run.** The engine refuses it (exit 86),
  and the app launches the model with a layer split instead. Both of its stress modes therefore
  ran layer.
- **The 35B's DFlash drafter is not used by the app's launch.** The planner turns it off: it
  needs 30.99 GiB against a 10.5 GiB budget on the expert tier. The drafter's head copy from
  beta.5 (`spec/0073`) is unchanged and was not re-measured.
- **Two parallel requests** were not tested, because the app launches `--parallel 1`.
- **A 32-lane GPU:** there is none here. The D700 rules sit inside `simd_width == 64` checks.
- **The throughput table** was measured with the user's idle CPU-only 14B server resident.
- **The real chat went through the engine's API, not the chat window.** The window was not
  checked by eye.
- **First-token logprobs, GPU against CPU:** reported, not gated.
- The tag is annotated, not signed.
