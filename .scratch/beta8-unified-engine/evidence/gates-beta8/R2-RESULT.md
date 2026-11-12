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
