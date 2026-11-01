# 74: beta.5 loads every model and crashes on the first chat (the 0.87.31-beta.6 release)

Status: ready-for-agent
Type: task

## Problem

The user reports that every model loads but chatting fails. From the XeonLLM logs
(`~/Library/Application Support/XeonLLM/logs/server-2026-10-31_*.log`, five sessions) and the
ToshLLM ones, the orchestrator found these causes on 2026-10-31.

### 1. The engine crashes on any prompt of 448 tokens or more on some models (exit 11)

Every session ends with:

    E ggml_metal_library_compile_pipeline_impl: kernel not found in any metal library:
      base = 'kernel_mul_mm_bf16e_f32_w_w64', name = 'kernel_mul_mm_bf16e_f32_w_w64_bci=0_...'
    [XeonLLM] the engine stopped (engine exited with code 11 ...) — restarting

Reproduced on the shipped engine (`dist/XeonLLM.app/.../bin/llama-bench`, sha256 of
llama-server `ed4841fc...`), card 1: Nemotron-3.5-Bolt-E4B-Q4_K_M `-p 256` gives 96.12 t/s,
`-p 512` hits the error and stops. The model has one BF16 tensor, `per_layer_model_proj.weight`
(k 2560, 10752 rows).

Cause: `ggml_metal_library_get_pipeline_mul_mm` (`ggml/src/ggml-metal/ggml-metal-device.cpp`,
the `snprintf(base, ... wide ? "_w" : "", w64 ? "_w64" : "")` line) turns `wide` on for BF16
(it is in the wide type list) when ne1 >= 448 and ne0 >= 4096, and `w64` on for every 64-lane
manual GEMM. `kernels/mul_mm_w64.metal` instantiates `_w_w64` for f16, q4_0, q4_1, q5_0, q5_1,
q8_0, mxfp4, pq2_0, ptq1_0 and the IQ types, but not for bf16e (the name BF16 takes on cards
without bfloat), nor for q2_K..q5_K. Those are listed as wide-capable too. A missing pipeline
is then dereferenced: exit 11. The beta.5 gates missed it: llama-bench ran `-p 0`, and the
test-backend-ops MUL_MAT cases never reach ne1 >= 448 with ne0 >= 4096 for BF16. The same
check applies to `kernel_mul_mm_id_%s_%s%s%s%s` (MUL_MAT_ID, with `_h`).

Chat triggers it every time: the app's system prompt plus the tool list are well over 448
tokens.

### 2. Tool servers never start

27 of 27 stdio MCP servers fail in every session: `failed to spawn 'uvx'` and
`failed to spawn 'npx'`. `uvx` is in `~/.local/bin`, `npx` in `~/.9remote/node/bin`. The engine
spawns the `--mcp-servers-json` servers itself with the app's environment, and a GUI app's PATH
has neither directory. `Sources/MCP/MCPStdioTransport.swift` adds only Homebrew and
/usr/local, and that applies only to the app's own transport, not to the engine's launch
(`Sources/Servers/Server.swift`). ToshLLM 0.87.30 logs show the same failures, so this is
inherited, not new.

### 3. Remote MCP over HTTPS fails

`proxying POST request to https://mcp.exa.ai:443/mcp` ->
`HTTPS requested but CPPHTTPLIB_OPENSSL_SUPPORT is not defined`. The engine is built without TLS.

### 4. The ToshLLM data was only half migrated

The settings were copied (87 keys against ToshLLM's 86) and so was the marker. The Application
Support folder was not: `~/Library/Application Support/XeonLLM` already existed (created
12:05 on 2026-10-31, before first launch), and `IdentityMigration` copies the folder only when
the new one is absent. Missing as a result: ToshLLM's `conversations.json` (3278 B, against
451 B in XeonLLM), `AudioRecovery.json`, `dynamic-moe/` and the rest.

### 5. The engine reports itself as "ToshLLM engine 0.87.31-beta.4"

The beta.5 bundle's llama-server contains spec/0073 (`dflash lm head copied` is in its strings),
so the code is beta.5. The version string is stale: `TOSH_VERSION` is passed through
`CMAKE_CXX_FLAGS` at configure time, and the incremental build did not reconfigure after
`VERSION` changed. The banner text "ToshLLM engine" also predates the rename.

### 6. About and Donate still point to upstream's author

`Sources/App/AboutTab.swift` lines 14-22: developer Engelbert Delgado, upstream's GitHub,
upstream's repository, a youpay sponsor link and a Binance Pay ID. The user wants the developer
to be Samer Kharboush and Repository/Donate to point to <https://github.com/SamerKharboush/xeonllm>.
The ToshLLM credit row stays.

### 7. Also seen, to triage

- `(CORS) skip non-localhost origin: http://10.139.172.6:8080`: the web UI is reached from
  the LAN address. Check that chat and tools work from that origin, or that the UI says why
  they don't.
- `the driver refused kernel_flash_attn_ext_pf_amd_dk256_..._lg16; the tile kernel takes the
  prefill`: a handled fallback, but it is printed on every prompt. Confirm the fallback is
  correct and cache the refusal.

## Change

Follow `specs/release-contract.md`. Briefs R3 (engine) and R4 (app), then the release.

## Comments

### 2026-11-01, the engine half (R3, Mocca, reviewed and re-gated by the orchestrator)

- `metal/0075`: the MUL_MAT and MUL_MAT_ID selectors ask the library for the composed name
  (`ggml_metal_library_has_function`) and drop `_w`, then `_w64`, when it is absent; a pipeline
  that is still null aborts with the kernel's name instead of a segfault. The single-library
  path reads `functionNames` once (orchestrator change; Mocca's version compiled a function
  lookup per matmul). `TOSH_METAL_CHECK_KERNELS=1` walks both selectors over every type x batch
  class x row count at init and exits non-zero on a missing name. New test_mul_mat /
  test_mul_mat_id cases at m 4096, n {448, 512, 1024}, k 2560 for every wide-capable type.
  Banner: `XeonLLM engine <VERSION>`.
- A `kernel_mul_mm_bf16e_f32_w_w64` was tried and removed: Nemotron-3.5-Bolt-E4B pp512 79.09
  +- 0.66 with it against 79.00 +- 0.74 on the fallback (dev build, card 1, `-r 2`), inside
  the noise.
- Gates, dev build `build-static` (llama-server sha256 `607fc6964658d3a5`), orchestrator run:
  MUL_MAT 1832/1832 and MUL_MAT_ID 936/936 on cards 0 and 1; FLASH_ATTN_EXT 1993/1993 on card 1
  with and without `TOSH_FA_AMD=1`; every op on card 1 13983/13983;
  `scripts/check-kernel-coverage.sh` 0 missing on both cards, and 3 missing on the shipped
  beta.5 (`kernel_mul_mm_bf16_f32_w`, `_bf16_f32_w_w64`, `_bf16e_f32_w_w64`). 85 of 85 patches
  apply to the pin.
- Prefill cost of the lookup: Qwen3-4B-Q4_K_M `llama-bench -p 512 -n 0 -r 3 -fa 1`, card 1,
  shipped beta.5 against the dev build, alternated twice: 82.49 / 82.50 and 82.44 / 82.48 t/s
  (sd <= 0.05). The user's idle app server was holding both cards during the run.
- Stress (`scripts/stress-release.sh`, Mocca's run on the dev build, app flags without the
  drafter): 17-18 PASS of 19 cells per model for Qwen3-0.6B/4B Q4_K_M/4B Q6_K/8B and
  Nemotron-E4B, tensor and layer; the one FAIL is Nemotron making no tool call. The shipped
  beta.5 segfaults on Nemotron at the 450-token band. Not run: the drafter, the 35B, the IQ2
  27B, `-ngl 0`. LFM3-1.7B cannot load (`unknown model architecture: 'lfm3'`), and
  Ternary-Bonsai PQ2_0 refuses tensor split (`RESHAPE cannot be tensor-split`).
- Version stamp: `scripts/build-engines.sh` and `scripts/llama-incremental-build.sh` re-stamp
  `-DTOSH_VERSION` from VERSION and fail the build if the binary does not carry it.
- The FA refusal is already logged once per kernel name (`ggml-metal-ops.cpp`, the refused
  set); no change.
