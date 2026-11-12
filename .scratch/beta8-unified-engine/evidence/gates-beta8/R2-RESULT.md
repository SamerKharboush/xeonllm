# Beta 8 R2 — engine gates on shipped binaries (PARTIAL: 4 of 10 sections)

Run: `/Users/sam/firellama`, branch `phase1-metal-d700-optimization` (HEAD `195949fcbf2870cc855e9052af9a6b1d3ddcde04`).
Sections run one at a time, in order, via `GATES_SECTIONS=S bash .scratch/beta8-unified-engine/evidence/gates-beta8/gates.sh`.
`gates.sh` / `srv.sh` / `repro.sh` untouched. No git commit/tag/push, no install, no user defaults, pid 747 untouched.

Time budget: started `Thu Nov 12 12:01:53 CET 2026`; stop rule 2 h 45 min = 14:46:53.
The `prefill` section alone needed ~60 min wall (and one re-run after the shell tool's timeout killed the first
attempt at 13:34), so sections after `prefill` could not be started inside the budget. Reported below is
everything that ran; the rest is **NOT RUN**, not failed.

---

## Table

| section | rc | verdict | evidence (quoted from log) |
|---|---|---|---|
| identity | 0 | **PASS** | `assert[bundle]: engine commit d81235049 == pin`<br>`assert[bundle]: bundle 0.87.31-beta.8 == VERSION`<br>`VERSION 0.87.31-beta.8`<br>`embedded version strings: 1`<br>`assert[bundle]: sha256 4f72303829f6fdda828163cb7bc68eade34eb9180d75f378b7712aa9b6e8ebb4` |
| ops | 0 | **PASS** | `card 0 ALL rc=0:   13983/13983 tests passed FAIL=0`<br>`card 1 ALL rc=0:   13983/13983 tests passed FAIL=0`<br>`card 0 FA TOSH_FA_AMD=1 rc=0:   1993/1993 tests passed FAIL=0`<br>`card 1 FA TOSH_FA_AMD=1 rc=0:   1993/1993 tests passed FAIL=0`<br>`card 0 FA TOSH_FA_AMD_DISABLE=1 rc=0:   0/0 tests passed FAIL=0`<br>`card 1 FA TOSH_FA_AMD_DISABLE=1 rc=0:   0/0 tests passed FAIL=0` |
| coverage | 0 | **PASS** | `# card 0: exit 0, missing 0`<br>`# card 1: exit 0, missing 0`<br>`PASS: 0 missing kernel names` |
| prefill | 0 (section rc) | **FAIL (1 of 20 rows)** | all rows `rc=0 rows=7` except:<br>`both cards 0,1 -sm tensor Ternary-Bonsai-2-27B-PQ2_0 (7206168928 bytes, over one card) rc=86 rows=0 handled (exit 86)` — allowed refusal<br>`35B host (-ngl 0) rc=134 rows=6` — **non-zero, only 6 of 7 bands** |
| preflight | — | **NOT RUN** | (budget) |
| engine | — | **NOT RUN** | (budget) |
| proofs | — | **NOT RUN** | (budget) |
| proofs8 | — | **NOT RUN** | (budget) |
| avx | — | **NOT RUN** | (budget) |
| repro | — | **NOT RUN** | (budget) |

Section scripts exited rc=0 in every case that ran (the `gates.sh` wrapper itself does not fail on a bad row,
so `prefill rc=0` is the wrapper's status, not a pass mark).

### prefill — all 20 quoted rows

```
card 0 Qwen3-0.6B-Q8_0 (639446688 bytes, fits one card) rc=0 rows=7
card 1 Qwen3-0.6B-Q8_0 (639446688 bytes, fits one card) rc=0 rows=7
card 0 Qwen3-4B-Q4_K_M (2497280256 bytes, fits one card) rc=0 rows=7
card 1 Qwen3-4B-Q4_K_M (2497280256 bytes, fits one card) rc=0 rows=7
card 0 Qwen3-4B-Q6_K (3306260704 bytes, fits one card) rc=0 rows=7
card 1 Qwen3-4B-Q6_K (3306260704 bytes, fits one card) rc=0 rows=7
card 0 Qwen3-8B-Q4_K_M (5027783488 bytes, fits one card) rc=0 rows=7
card 1 Qwen3-8B-Q4_K_M (5027783488 bytes, fits one card) rc=0 rows=7
both cards 0,1 -sm layer Qwen3-14B-Q4_K_M (9001753376 bytes, over one card) rc=0 rows=7
both cards 0,1 -sm tensor Qwen3-14B-Q4_K_M (9001753376 bytes, over one card) rc=0 rows=7
both cards 0,1 -sm layer Nemotron-3.5-Bolt-E4B-Q4_K_M (6180446208 bytes, over one card) rc=0 rows=7
both cards 0,1 -sm tensor Nemotron-3.5-Bolt-E4B-Q4_K_M (6180446208 bytes, over one card) rc=0 rows=7
card 0 LFM3-1.7B-F16 (3466626336 bytes, fits one card) rc=0 rows=7
card 1 LFM3-1.7B-F16 (3466626336 bytes, fits one card) rc=0 rows=7
both cards 0,1 -sm layer Ternary-Bonsai-2-27B-PQ2_0 (7206168928 bytes, over one card) rc=0 rows=7
both cards 0,1 -sm tensor Ternary-Bonsai-2-27B-PQ2_0 (7206168928 bytes, over one card) rc=86 rows=0 handled (exit 86)
both cards 0,1 -sm layer Underdog-Saluki-27B-1.0-IQ2-mix (7898369152 bytes, over one card) rc=0 rows=7
both cards 0,1 -sm tensor Underdog-Saluki-27B-1.0-IQ2-mix (7898369152 bytes, over one card) rc=0 rows=7
35B host (-ngl 0) rc=134 rows=6
```

`35B host` failure detail, from `out/pp-35b-host.err` (MoE model, CPU path, `-ngl 0`):

```
/vendor/llama.cpp/ggml/src/ggml-backend.cpp:2193: GGML_ASSERT(id >= 0 && id < n_expert) failed
.scratch/.../gates.sh: line 13: 37283 Abort trap: 6   perl -e 'alarm shift; exec @ARGV' "..."
```

Six bands completed (pp 16/128/256/448/512/1024); the abort landed in the 7th band (2048) inside
`llama_benchi → test_prompt → llama_context::decode`. It is an MoE expert-index assert, unrelated to
Metal: this row loads `-ngl 0` so no kernel runs on the cards. Not worked around; the shipped engine is
untouched. Re-verify this row before calling section 3.3 clean.

---

## Method lines

- **identity**: shipped binaries at `dist/XeonLLM.app/Contents/Resources/bin`, engine commit `d81235049`,
  VERSION `0.87.31-beta.8`. Shipped engine sha256 prefix (llama-server, from `shasum -a 256` and
  `assert[bundle]`): **`4f72303829f6fdda`** (full: `4f72303829f6fdda828163cb7bc68eade34eb9180d75f378b7712aa9b6e8ebb4`).
  Other prefixes in the same section: llama-bench `195e16e0cdb71429`, test-backend-ops `2c7592b72190f3a4`.
- **ops**: same binaries, `test-backend-ops -b MTL0`, cards 0 and 1 (`GGML_METAL_DEVICE_INDEX`), two passes
  (`-o FLASH_ATTN_EXT` with `TOSH_FA_AMD=1` and `TOSH_FA_AMD_DISABLE=1`).
- **coverage**: same binaries, engine self-check `TOSH_METAL_CHECK_KERNELS=1`, cards 0 and 1.
- **prefill**: `llama-bench -m $M/<model>.gguf -ngl 99 -fa 1 -p 16,128,256,448,512,1024,2048 -n 0 -r 1 -o csv`,
  one card (`GGML_METAL_DEVICE_INDEX=c`) for models < 5905580032 bytes, both cards
  (`GGML_METAL_DEVICE_LIST=0,1 -sm layer|tensor`) at or above it, plus one host row
  `-ngl 0` on `Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf`. No throughput numbers are quoted here, so no
  per-number method line beyond the above.
- **proofs / proofs8 / repro (NOT RUN)**: would be, per `gates.sh`, card 1 (`GGML_METAL_DEVICE_INDEX=1`),
  `Qwen3-4B-Q4_K_M.gguf -ngl 99 -fa 1`, `-ub 128`, `-r 5` (proofs), `-ub 128 -p 512 -n 128 -d 6144 -r 3` and
  server arms `-ub 128 -b 2048 -c 8192 -t 12 --jinja --parallel 1 --cache-ram 0` (0083);
  `Qwen3.6-27B-...-Q6_K.gguf -ngl 12 -c 4096 -ub 128 -b 512 -t 12 -fa on --jinja --parallel 1 --cache-ram 0`,
  one card vs `--split-mode layer` over list 0,1, plus `TOSH_GDN_STATE_FUSION_MULTI=1` control (0084);
  `repro.sh ship` on the 14B layer split over both cards (0078). All unrun.

## DiagnosticReports

- Before the first section (`gates-identity.log` line 1, 12:02:21):
  `codesign_2026-11-11-211515_Sams-Mac-Pro.diag`, `cp_2026-11-11-092927_Sams-Mac-Pro.diag`, `Kernel-2026-11-11-083524.panic`
- After the last section (`gates-prefill.log` line 24, 14:35:00): identical three names, same order.
- No `NEW CRASH REPORT` line and no exit 9 appeared in any log. `chk` ran after every GPU program.
- Independent of the gate script, a background monitor (`monitor-R2.log`) sampled `panic|watchdog|gpuRestart`
  counts and process counts every 60 s for the whole run: `grep -cE 'VIOLATION|CRASH'` on it = `0`; last entry
  `14:39 srv=0 bench=0 tbo=0 cli=0 clang=0`. The pre-existing `Kernel-2026-11-11-083524.panic` predates this run.

## Skipped

- `preflight`, `engine`, `proofs`, `proofs8`, `avx`, `repro`: not run — 2 h 45 min budget reached (stop rule
  14:46:53) while `prefill` was still finishing. Prefill needed ~60 min per full pass and was run twice
  because the first attempt was killed by the shell tool's 50-minute timeout, not by the gate harness.
- 0083 pp512/tg128 rows per process, 0084 first-120-char texts and kernel lines: **not available**, sections not run.
- Nothing else skipped; no script bug hit (the only re-run was caused by my own tool timeout, and the re-run
  reproduced the same results including the same `rc=134` 35B host abort).

---

# Second pass — 14:47:15 to 15:53:12 CET (same rules, no section re-run from pass 1)

identity / ops / coverage / prefill not re-run. 35B host abort not investigated (separate ticket).

| section | rc | verdict | evidence (quoted from the log) |
|---|---|---|---|
| preflight | 0 | **PASS** | `preflight rc=0`<br>`preflight[baseline]: -ngl 0 served, produced 32 tokens`<br>`preflight[baseline]: -ngl 99 served, produced 32 tokens`<br>`preflight[baseline]: drop counter reads 1 on a forced drop (the control passes)`<br>`preflight[baseline]: --version -> version: 0.6.0-dev (build 11429, commit d81235049)` |
| engine | 0 | **PASS** | `test-engine rc=0`<br>`patches/llama/server/tests/test_mcp_cancel.py: ran 20, passed 20, failed 0, skipped 0`<br>`OK` (`out/test-engine.log` last line: `Ran 20 tests in 78.930s`), and `grep 'failed [1-9]'` over the whole `out/test-engine.log` = `0` |
| proofs | 0 | **NOT PROVEN — script bug, skipped** | `== section 2 proofs (wave64 lines, rows8 / full-tg controls; card 1, models under one card)` is followed by the six wave64/aligned lines on both cards, then *no* `tg128` line at all. Twice identical (log `gates-proofs.log` and `gates-proofs-rerun.log`): header at `15:01:29` → `GATES DONE` at `15:02:01` (32 s), header at `15:14:16` → `GATES DONE` at `15:14:49` (33 s). The 6 arms each ran ~5 s (`sleep 5` × 6 = 30 s of the total) and printed nothing. |
| proofs8 | 0 | **PARTIAL — script bug on the bench arms; 0083 text + 0084 all pass** | `0083 new process 1 rc=127` / `0083 new process 2 rc=127` / `0083 w64 process 1 rc=127` / `0083 w64 process 2 rc=127`<br>`0083 text identical`<br>`0084 twocard12 identical to one12`<br>`0084 control differs (expected)` |
| avx | 0 | **PASS** | `llama-bench: 0` `llama-perplexity: 0` `llama-server: 0` `test-backend-ops: 0` |
| repro | 0 | **PASS** | `ship: 200 751.9 b'{"choices":[{"finish_reason":"length","index":0,"message":{"role":"assistant","content":"","reasoning_conten timeouts=0` |

### The script bug (proofs + the 0083 bench half of proofs8)

`gates.sh` line 85 (proofs) and line 91 (0083 bench) invoke the `al` alarm helper **through `env`**:

```sh
env $e=1 GGML_METAL_DEVICE_INDEX=1 al 900 $B/llama-bench -m $M/$m.gguf ... -o csv 2>/dev/null | tail -1 | awk ...
```

`al` is a bash *function*; `env` can only execute a program. Result: `env: al: No such file or directory`, exit 127, no
benchmark ever starts. That is exactly why the proofs section finished in 33 s and the 0083 rows are all `rc=127`.
`gates.sh` line 13 discards the stderr of the arm (`2>/dev/null`), so no error text is recoverable from the log.

Not worked around: no GPU command of mine was run to stand in for the broken lines. Both sections must be re-run
after `gates.sh` is fixed (put `al 900 ...` before the `env` prefix, or drop `env` for the time limit).

Consequences for the pass criteria:

- **proofs**: the six `tg128` lines (X / TOSH_MV_ROWS8_DISABLE / TOSH_FULL_TG_DISABLE × Qwen3-4B-Q4_K_M /
  Qwen3-0.6B-Q8_0) do not exist. The X-above-ROWS8_DISABLE check is unproven. The wave64 / aligned mat-vec banner
  lines did come out, on both cards:
  ```
  card 0: ggml_metal: aligned mat-vec reads ON by amdgpu_gfx600 (override with TOSH_MV_ALIGN=1 or =0)
  card 0: ggml_metal: device 0: AMD Radeon HD - FirePro D700 (peer group 0, not bridged) probed SIMD-group width = 64 (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)
  card 0: ggml_metal: wave64 decode ON: quantized/f16/bf16 mat-vec on GPU (see the allowlist in ggml_metal_library_get_pipeline_mul_mv)
  card 1: ggml_metal: aligned mat-vec reads ON by amdgpu_gfx600 (override with TOSH_MV_ALIGN=1 or =0)
  card 1: ggml_metal: device 0: AMD Radeon HD - FirePro D700 (peer group 0, not bridged) probed SIMD-group width = 64 (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)
  card 1: ggml_metal: wave64 decode ON: quantized/f16/bf16 mat-vec on GPU (see the allowlist in ggml_metal_library_get_pipeline_mul_mv)
  ```
- **proofs8 / 0083**: the four `p83-*.csv` files are empty and `p83-*.err` holds only the `env: al` failure, so there
  are **no pp512 @ d6144 and no tg128 rows per process to quote** — the "new above w64 on both" check is unproven.
  The 0083 *text* arm (served by `srv.sh`, unaffected) passed: `0083 text identical`.

### proofs8 / 0084 — texts, first 120 chars each (`out/t84-*.txt`)

```
t84-one12.txt:        Here's a thinking process:

1.  **Understand User Request:** The user wants an explanation of what a binary search tree 
t84-two12.txt:        Here's a thinking process:

1.  **Understand User Request:** The user wants an explanation of what a binary search tree 
t84-two12-multi.txt:  Here000000000000000000000000000000000000000000000000000000000000000|
```

(The characters shown are the literal file contents; the first two texts contain real newlines.)

### proofs8 / 0084 — kernel lines, quoted from `gates-proofs8.log`

```
kernels one12: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1 
kernels two12: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0 
kernels two12-multi: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1 
```

Matches the pass criteria exactly: one-card shows `rows=1_fold=1`, two-card shows only `rows=0_fold=0`, control shows
`rows=1_fold=1`. `cmp` line for the control, quoted:
`/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/out/t84-one12.txt /Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/out/t84-two12-multi.txt differ: char 5, line 1`.

## Method lines for the six sections of this pass

- Shipped engine: `dist/XeonLLM.app/Contents/Resources/bin`, sha256 prefix **`4f72303829f6fdda`** (llama-server),
  VERSION `0.87.31-beta.8`, engine commit `d81235049`, build 11429 (per `gates-identity.log`).
- **preflight**: `tools/ab.sh --baseline $B/llama-server --model /Users/sam/models/Qwen3-0.6B-Q8_0.gguf --split layer --preflight-only`.
- **engine**: `scripts/test-engine.sh` with `LLAMA_SERVER_BIN_PATH=<repo>/dist/XeonLLM.app/Contents/Resources/bin/llama-server`; the server under test is the shipped bundle binary.
- **proofs (attempted, no data)**: card 1 (`GGML_METAL_DEVICE_INDEX=1`), `Qwen3-4B-Q4_K_M` and `Qwen3-0.6B-Q8_0`, `-ngl 99 -fa 1 -p 0 -n 128 -r 5`, arms `X`, `TOSH_MV_ROWS8_DISABLE`, `TOSH_FULL_TG_DISABLE`.
- **proofs8 (attempted, no data)**: card 1, `Qwen3-4B-Q4_K_M -ngl 99 -fa 1 -ub 128 -p 512 -n 128 -d 6144 -r 3`, arms `TOSH_FA_PF_W64=1` (w64) vs `XEONLLM_NOOP=1` (new), 1 process each.
- **proofs8 text arms (ran)**: `srv.sh` on card 1, `Qwen3-4B-Q4_K_M.gguf -ngl 99 -c 8192 -ub 128 -b 2048 -fa on -t 12 --jinja --parallel 1 --cache-ram 0`, prompt = `evidence/18/prompt6k.txt` (~6k tokens), `max_tokens 64 temperature 0.0 seed 1`; arms new vs `TOSH_FA_PF_W64=1`.
- **0084 (ran)**: `Qwen3.6-27B-Heretic-...-Q6_K.gguf -ngl 12 -c 4096 -ub 128 -b 512 -t 12 -fa on --jinja --parallel 1 --cache-ram 0 -v`, `max_tokens 64 temperature 0.0 seed 1`; one12 = `GGML_METAL_DEVICE_INDEX=1`, two12 = `GGML_METAL_DEVICE_LIST=0,1 --split-mode layer`, control = same as two12 plus `TOSH_GDN_STATE_FUSION_MULTI=1`.
- **avx (ran)**: `otool -tv` over every executable Mach-O in `dist/XeonLLM.app/Contents/Resources/bin`; four found.
- **repro (ran)**: `repro.sh ship`, 14B layer split over both cards, ~5.4k prompt.

No throughput number is quoted anywhere in this document, so no per-number method line is needed beyond the above.

## DiagnosticReports, second pass

- Before the first section of this pass (`gates-preflight.log` line 1, 14:48:09):
  `codesign_2026-11-11-211515_Sams-Mac-Pro.diag`, `cp_2026-11-11-092927_Sams-Mac-Pro.diag`, `Kernel-2026-11-11-083524.panic`
- After the last (`gates-repro.log` line 6, 15:47:38): identical three names, same order.
- No `NEW CRASH REPORT` and no exit 9 in any of the six logs. The pre-existing `Kernel-2026-11-11-083524.panic` still predates the whole task.
- Independent monitor `monitor-R2b.log` (panic/watchdog/gpuRestart count + process census every 60 s):
  `grep -cE 'VIOLATION|CRASH'` = `0`; last entry `15:52 srv=0 bench=0 tbo=0 clang=0 gates=0`. One `NOTE: 2 GPU programs at once`
  at `15:30`, during the handoff between proofs8 (GATES DONE `15:28:43`) and avx (`15:29:55`); avx itself runs no GPU
  program (`otool` only), so no two GPU sections overlapped.

## Skipped in this pass

- **proofs**: script bug (`env ... al`), skipped per the rules; no GPU substitute run. Re-run after the fix.
- **proofs8 bench arms (0083 pp512/tg128)**: same script bug (`env ... al` at line 91), same handling; the 0083 text
  arm and the whole 0084 section did run and pass.
- The 35B host abort (`prefill`, from pass 1): not investigated, as instructed.
