# The XeonLLM release contract

Status: binding for every release from 0.87.31-beta.6 on. Every delegated brief that builds,
changes or ships XeonLLM links this file, and the orchestrator checks every item below before
tagging. A release that fails an item does not ship; the failing item goes into the release
ticket under "Not covered" only if the user agrees to ship without it.

Why this exists: beta.5 passed every gate it had and still crashed on the first chat. The
gates measured generation (`-p 0`), the op tests ran shapes that never reach the 64-lane wide
GEMM, and nobody chatted with the shipped app. The engine reported itself as beta.4 and as
"ToshLLM", and the gates did not notice. This contract closes those gaps.

## 1. Identity

| item | required value |
|---|---|
| app name, bundle, DMG, volume | XeonLLM, `dev.xeonllm.app`, `XeonLLM-v<VERSION>-noavx2.dmg`, volume `XeonLLM` |
| About: developer | Samer Kharboush, handle `SamerKharboush`, <https://github.com/SamerKharboush> |
| About: repository | <https://github.com/SamerKharboush/xeonllm> |
| About: Donate | opens <https://github.com/SamerKharboush/xeonllm>; shows no other person's payment ID, QR code or sponsor link |
| credit | the About tab, README, AUTHORS.md and THIRD_PARTY_NOTICES.md credit ToshLLM by Engelbert Delgado (<https://github.com/engeldlgado/toshllm>) as the upstream; GPL copyright headers in source files are kept, never removed |
| engine banner | `llama-server` logs `XeonLLM engine <VERSION>` and `llama-bench` prints the same; `<VERSION>` equals the `VERSION` file |
| kept on purpose | `TOSH_*` env switches, `TOSH*` plist keys, `X-ToshLLM-*` webhook headers, the `toshllm-settings` import format, CITATION.cff / .zenodo.json (they describe upstream's record) |

## 2. The optimisations that must be in every release

A release ships only if all of these are present in the bundled engine and app. "Present" is
checked on the shipped binaries, not the dev tree.

- **The whole patch series.** `scripts/check-patch-series.sh` applies every patch under
  `patches/llama/*/` to the pin in `vendor/` with 0 failures. Count it and write the count in
  the release notes. No patch is dropped to make a build pass; a patch that stops applying is
  a release blocker.
- **The AVX1 engine.** 0 AVX2/FMA mnemonics in every bundled binary (the build check in
  `scripts/build-engines.sh`).
- **The 64-lane paths are live.** A server log on this Mac shows, for each card:
  `probed SIMD-group width = 64`, `wave64 decode ON`, `aligned mat-vec reads ON`.
- **The DFlash drafter head on the card** (spec/0073): with a host target and a drafter on a
  card, `-lv 4` prints `dflash lm head copied to`; with `TOSH_DFLASH_HEAD_HOST=1` it prints
  `kept on the host`.
- **The mat-vec thresholds** (metal/0074 and its predecessors): `TOSH_MV_ROWS8_DISABLE=1`
  changes tg128 on Qwen3-4B-Q4_K_M by more than the noise, proving the rule is in the binary.
- **The app's launch defaults.** The server log header shows `TOSH_FA_AMD=1`, the placement
  rule (`placement: card` or `host` per the ticket 67 rule), and the DFlash auto line.
- **The data migration** from ToshLLM (see section 5).

When a new optimisation lands, add a line here with its proof-of-presence check in the same
commit.

## 3. Engine gates (shipped binaries, card 0 and card 1)

All with `dist/XeonLLM.app/Contents/Resources/bin/*`, `GGML_METAL_DEVICE_INDEX=0` then `=1`.

1. `test-backend-ops -b MTL0` **for every op**, not only MUL_MAT / MUL_MAT_ID / FLASH_ATTN_EXT:
   0 FAIL. Also once with `TOSH_FA_AMD=1`.
2. **Kernel coverage.** `scripts/check-kernel-coverage.sh`: for every quant type the Metal
   backend accepts, and every batch size class (1, 2-8, 9-32, 33-191, 192-447, 448-1023,
   >= 1024) at row counts below and above every row floor (2048, 4096), the pipeline name the
   host selector composes for MUL_MAT and MUL_MAT_ID exists in the shipped metallib. Zero
   missing names. (beta.5 composed `kernel_mul_mm_bf16e_f32_w_w64`, which was never
   instantiated.)
3. **Prefill, not only decode.** `llama-bench -p 16,128,256,448,512,1024,2048 -n 0 -r 1` on
   every model in the stress set (section 4) completes on both cards. A missing kernel, a
   driver refusal that is not handled, or a non-zero exit fails the release.
4. **The preflight gate** (`-ngl 0` and `-ngl 99` serve, the forced-drop control reads 1)
   and `assert_artifact` (engine commit == pin, bundle version == `VERSION`, engine banner
   version == `VERSION`).
5. `scripts/test-engine.sh` against the shipped `llama-server`: 0 failures.

## 4. The stress test (the shipped app's real launch)

`scripts/stress-release.sh` reproduces the launch the app performs. It reads the `args:` and
`env:` lines of the newest server log under `~/Library/Application Support/XeonLLM/logs/`
(or builds them the way `Sources/Servers/Server.swift` does) and starts the shipped
`llama-server` with them. It never touches the user's running app.

The stress set is every model in `/Users/sam/models` that the placement rule can load,
at least: Qwen3-0.6B-Q8_0, Qwen3-4B-Q4_K_M, Qwen3-4B-Q6_K, Qwen3-8B-Q4_K_M, Qwen3-14B-Q4_K_M,
Nemotron-3.5-Bolt-E4B-Q4_K_M (it has a BF16 tensor), LFM3-1.7B-F16 (F16 weights), one IQ/PQ
model (Ternary-Bonsai-2-27B-PQ2_0 or Underdog-Saluki-27B IQ2), the 35B (Ornith-1.0-35B Q6_K,
host placement) with and without its DFlash drafter. If a model cannot be loaded, name it and
the reason in the report.

Per model, through `/v1/chat/completions` with the app's chat template (`--jinja`):

- prompts of about 16, 300, 450, 520, 1100, 4200 and 8300 tokens (the bands around every
  GEMM floor), each answered with at least 64 tokens;
- a 6-turn conversation that reuses the cache (`--cache-reuse`), and one that exceeds the
  cache and must evict;
- a request with tools enabled (`--tools all`) that makes at least one tool call;
- two concurrent requests where `--parallel` allows it, and a cancelled stream followed by a
  new request;
- both split modes the app offers (layer and tensor) on the two cards, and `-ngl 0`.

A cell passes when the server stays up, the log has no `kernel not found`, no `exited with
code`, no `GGML_ASSERT`, the answer is non-empty and on topic (a reviewer reads a sample of
answers), and greedy text is byte-identical to `-ngl 0` for the same prompt where the model
fits both ways. The report is a table: model x cell -> pass/fail with the log line that failed.

## 5. App gates

- `swift test`: no failures beyond the known `MCPStdioTransportTests` race (name each failure).
- **Migration.** From a profile that has `~/Library/Application Support/ToshLLM` and the
  `dev.engel.toshllm` defaults, first launch copies settings, Keychain items, and every item of
  the Application Support folder into XeonLLM's, **even if the XeonLLM folder already exists**:
  items absent in the new folder are copied, `conversations.json` and `projects.json` are
  merged by id with the new copy winning, nothing of ToshLLM's is moved or deleted, and the
  copy is idempotent. Users already migrated by the beta.5 logic get the folder merge once.
- **Tool servers start.** The engine and the app's MCP transport start `npx`/`uvx` servers
  installed in the user's own PATH (`~/.local/bin`, a node in `~/.nvm`, `~/.volta`,
  `~/.9remote/node/bin`, Homebrew, ...): the PATH comes from the user's login shell, read once
  with a timeout, plus the fixed extras. A server whose command is not found is reported in the
  UI by name, not only in the log.
- **Remote MCP over HTTPS** either works or is refused with a message the user sees (the
  engine is built without `CPPHTTPLIB_OPENSSL_SUPPORT`).
- The mounted DMG: bundle id, version, `TOSHNoAVX2` and `TOSHUpdatesDisabled` true,
  `codesign --verify --deep`, the DMG window layout read from `.DS_Store` (the method in
  ticket 73).
- **One real chat in the built app**: launch `dist/XeonLLM.app` against a test profile, load
  a model, send a message, get an answer. A screenshot or the server log of that chat goes in
  the release ticket.

## 6. Performance claims

`CLAUDE.md` "Performance claims" applies to every number in the notes and README: method line
(engine path and sha256 prefix, pinned commit, model and quant, ctx, batch, N, warmups
discarded), no percentage against a modelled ideal, a control proven to take effect, fits
judged by residuals against the noise floor, configurations that cannot run named, never
"faster" for a split-mode pair. Numbers are measured on the shipped engine; a dev-tree number
says so.

## 7. Delegation rules

- Every brief to an implementer names this file and the sections it must satisfy.
- The implementer never commits, tags, pushes, installs into /Applications, or edits
  `dist/` release artifacts unless the brief says so. The orchestrator reruns every gate it
  reports before committing.
- An env switch, file, kernel or API the implementer names must exist (grep it) or be marked
  as new. Claims about other projects cite a fetched source.
- Partial results are reported as partial; a gate that did not run is listed as not run.
