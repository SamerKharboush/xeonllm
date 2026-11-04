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

### 2026-11-01, the app half (R4, Mocca, reviewed and re-gated by the orchestrator)

- Cause 4: `IdentityMigration` merges the ToshLLM folder item by item even when XeonLLM's
  exists (missing items copied, no file overwritten, `conversations.json` / `projects.json`
  united by `id` with the XeonLLM copy winning, atomic write). A second marker,
  `migratedFromToshLLMFolderV2`, gives users migrated by beta.5 the merge once. ToshLLM's folder
  is never moved or changed. The user's files have the expected shape (arrays keyed by `id`:
  8 ToshLLM conversations, 2 XeonLLM).
- Cause 2: `Sources/App/UserShellPath.swift` reads the login shell's PATH once (3 s deadline,
  silent fallback; 0.24 s on this Mac) and adds the usual install locations; used for the
  engine's environment and for the app's own stdio MCP transport. All 24 servers in the newest
  log's `args:` resolve with it (`uvx` -> `~/.local/bin`, `npx` -> `~/.9remote/node/bin`; none
  started). A `failed to spawn` line in the engine log now shows under that server in the MCP
  settings.
- Cause 3: no app change. App-configured remote servers already reach the engine through the
  bundled Python relay (`SymPyToolsService.remoteEntry` -> `remote.py`); the failing request
  was the web UI's `--ui-mcp-proxy` forwarding a browser-side https server. Open: refuse or
  relay https in the UI proxy.
- Cause 6: About, the docs' credits, the toolbar heart, the issue and update URLs point to
  Samer Kharboush and `SamerKharboush/xeonllm`; Donate opens the repository. `Donate.swift`,
  `Assets/binance-qr.png` and the Binance/USDT/sponsor strings are gone. The ToshLLM credit row
  and the GPL headers stay.
- CORS: Mocca added `--cors-origins "*"` under LAN discovery; the orchestrator removed it. The
  engine does not block the request, it only omits the header and logs
  (`tools/server/server-http.cpp:341`), and the web UI opened from the LAN address calls its own
  origin, where CORS does not apply. `*` would let any page in the browser drive the tool
  servers. The warning is noise; no change.
- Gates (orchestrator): `swift build` OK; `swift test` 510 tests, 16 skipped, 3 assertion
  failures all in `MCPStdioTransportTests.testAnswersRacingTheirDeadlinesResolveEachRequestOnce`
  (the known race); `check-translations.py` OK; `engeldlgado` only in headers and the credit
  row; no `binance` in Sources, Tests, Assets, make-app.sh.

### 2026-11-04, the release record (orchestrator)

**Why chatting failed after a good load.** Three causes, each reproduced and fixed:
- The 448-token crash (cause 1, `metal/0075`).
- The 14B on both cards at the saved `-c 32768`: 6926 MiB per card against 6144 (3954 weights +
  2688 KV + 284 compute). The driver paged, a long prefill's command buffer hit the macOS GPU
  watchdog (`kIOAccelCommandBufferCallbackErrorTimeout`), and every later request returned HTTP
  500 "Compute error.". Fixed by the context fit (ticket 75: the 14B launches at 16384, measured
  5613 / 5649 MiB per card) and shorter prefill command buffers (`metal/0078`; the repro on the
  shipped engine serves 200 where the control returns 500).
- A model behind a symlink was sized as the link (62 bytes): the 28 GB 35B Q6_K was placed on both
  cards whole and the Mac panicked (2026-11-04 01:15, spinlock timeout in
  `IOAccelSysMemory::unwire`). Fixed in `f0cae71`; the 35B takes the expert tier wherever its path
  points, and the drafter planner, fooled the same way, now turns the drafter off for it.

**The reboots** ("one of the tests always make device dead or restart"): the 2026-11-03 panics
were the 7.2 GB PQ2_0 27B on card 0 alone (WindowServer watchdog); the 2026-11-04 panic was the
symlinked 35B. `scripts/stress-release.sh` now refuses both (one card: exit 3; every layer of a
model over both cards on the cards: a REFUSED row, no server), sizing with `stat -L`. Contract
section 3.3.

**Stress, contract section 4, the rebuilt beta.6 app's real launch** (test bundle
`dev.xeonllm.gatetest`, saved ctx 32768, tensor split; `evidence/gates-beta6/out/set/`):
- Qwen3-0.6B, Qwen3-4B Q4_K_M and Q6_K, Qwen3-8B, Nemotron-3.5-Bolt-E4B: tensor and layer 20 PASS
  1 SKIP each, ngl0 3 PASS; layer == tensor byte-identical. Nemotron launches at 31744.
- Qwen3-14B (app launch at 16384): layer and tensor 20 PASS 1 SKIP (`out/stress-14b-ctxfit*`).
- Ternary-Bonsai-2-27B PQ2_0 (both cards): the app turns the saved tensor split into a layer
  split for this model (`tensorSplitLimit`, the engine refuses it with exit 86), so both stress
  modes ran `--split-mode layer`. 19 PASS 1 SKIP, and the evict cell timed out at the 900 s
  client limit with the engine still prefilling; rerun with 2700 s: evict PASS (20549 tokens,
  1145 s) and after-evict PASS in both runs (`out/set/pq2-evict-*`). A tensor split of it is not
  covered: it cannot run.
- Ornith-1.0-35B Q6_K (expert tier on card 1, no drafter; the stress "tensor" mode is the app's
  logged launch, so one card): 20 PASS 1 SKIP, ngl0 3 PASS
  (`out/set/ornith-1.0-35b-Q6_K/`).
- LFM3-1.7B: does not load (`unknown model architecture: 'lfm3'`), no cells.
- parallel2 SKIP everywhere: the app launches `--parallel 1`.
- No watchdog, assert or exit lines in any server log.
- GPU vs CPU text (reported, not gated): identical on the 0.6B and the PQ2; the quantised models
  diverge partway through an answer.

The real chat: the 14B through the test app's engine API (port 18099), 200 tokens at 6.70 tok/s,
`out/realchat-14b.json`; it went through the API, not the chat window.
