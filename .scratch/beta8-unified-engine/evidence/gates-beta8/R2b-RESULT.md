# Beta 8 R2b — engine gates on the R1b shipped binaries

Run: `/Users/sam/firellama`, branch `phase1-metal-d700-optimization` (HEAD `d0ea97c8edf1935e8cab082d791ca7230bfb27d5`).
Sections run one at a time, in the order given, via
`GATES_OUT=out-b GATES_SECTIONS=S bash .scratch/beta8-unified-engine/evidence/gates-beta8/gates.sh`, each started with
`nohup ... &` and waited to its `GATES DONE`. Logs: `gates-S-b.log` for each S. `out/` was not touched by this run
(the repro section's own `repro.sh` writes `out/repro-ship.*` by default; it was run unchanged). No git commit/tag/push,
no install, no user defaults, no query of 127.0.0.1:8080, pid 747 untouched. No GPU program ran outside a section;
only one section ran at a time.

Start `Fri Nov 13 00:47:41 CET 2026`. Stop rule 2 h 45 min = `03:32:41`; all ten sections finished at `02:46:23`, inside budget.

## Table

| section | rc | verdict | quoted evidence (from `gates-S-b.log`) |
|---|---|---|---|
| identity | 0 | **PASS** | `63eb2a01af361672` · `93db3d0cd285ec50` · `b0f4e727923bd65f` · `version: 0.6.0-dev (build 11429, commit d81235049)` · `embedded version strings: 1` · `VERSION 0.87.31-beta.8` · `assert[bundle]: engine commit d81235049 == pin` · `assert[bundle]: bundle 0.87.31-beta.8 == VERSION` · `assert[bundle]: sha256 63eb2a01af3616727827eb7bcdf90acf5b4919658cced1251575a4f8190c2221` |
| ops | 0 | **PASS** | `card 0 ALL rc=0:   13983/13983 tests passed FAIL=0`<br>`card 0 FA TOSH_FA_AMD=1 rc=0:   1993/1993 tests passed FAIL=0`<br>`card 0 FA TOSH_FA_AMD_DISABLE=1 rc=0:   0/0 tests passed FAIL=0`<br>`card 1 ALL rc=0:   13983/13983 tests passed FAIL=0`<br>`card 1 FA TOSH_FA_AMD=1 rc=0:   1993/1993 tests passed FAIL=0`<br>`card 1 FA TOSH_FA_AMD_DISABLE=1 rc=0:   0/0 tests passed FAIL=0` |
| coverage | 0 | **PASS** | `# path: engine self-check (TOSH_METAL_CHECK_KERNELS=1)`<br>`# card 0: exit 0, missing 0`<br>`# card 1: exit 0, missing 0`<br>`PASS: 0 missing kernel names` |
| prefill | 9 | **INCOMPLETE** (stopped by the wrapper's crash check after 12 of 20 rows; remaining 8 rows **NOT RUN**) | see "prefill — the stop" below |
| preflight | 0 | **PASS** | `preflight rc=0`<br>`preflight[baseline]: --version -> version: 0.6.0-dev (build 11429, commit d81235049)`<br>`preflight[baseline]: -ngl 0 served, produced 32 tokens`<br>`preflight[baseline]: -ngl 99 served, produced 32 tokens`<br>`preflight[baseline]: drop counter reads 1 on a forced drop (the control passes)` |
| engine | 0 | **PASS** | `test-engine rc=0`<br>`patches/llama/server/tests/test_mcp_cancel.py: ran 20, passed 20, failed 0, skipped 0` (last suite in `out-b/test-engine.log`) |
| proofs | 0 | **PASS** | see "proofs" below |
| proofs8 | 0 | **PASS** | `0083 text identical` · `0084 twocard12 identical to one12` · `0084 control differs (expected)` — see below |
| avx | 0 | **PASS** | `llama-bench: 0` · `llama-perplexity: 0` · `llama-server: 0` · `test-backend-ops: 0` |
| repro | 0 | **PASS** | `ship: 200 448.1 ... timeouts=0 text ok 'Okay, the user asked why the sky is blue and then repeated a'` |

The wrapper itself exits 9 only on a new panic/watchdog/gpuRestart report, so a `rc=0` means "ran to GATES DONE", not
"every gate row passed". The verdicts above are judged from the quoted lines.

## prefill — the stop, and what is missing

Twelve rows printed, all as required, then the wrapper stopped (the `NEW CRASH REPORT` line is quoted verbatim from the log; its three names are the old top-3, not new reports — see the correction at the end):

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
NEW CRASH REPORT after pp-Nemotron-3.5-Bolt-E4B-Q4_K_M-tensor: XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag  - STOP
```

That is a false stop, from a wrapper bug, not a crash and not a gate failure:

- The `chk` ran at `01:26:50` (end of the ops section). Between then and the Nemotron row (`out-b/pp-Nemotron-3.5-Bolt-E4B-Q4_K_M-both-tensor.csv`
  rows timestamped `2026-11-13T01:47:43Z` … `02:05:xxZ`), the system pruned three old reports from
  `/Library/Logs/DiagnosticReports` — `Kernel-2026-11-11-083524.panic`, `WindowServer_2026-11-10-213045_...spin`,
  `WindowServer-2026-11-10-213042.ips` (they are in `diagreports-before-b.txt`, written `Nov 12 23:42:37`, and gone now).
  The pre-R2b `chk` compared only the **count** of `panic|watchdog|gpuRestart` names, so a falling count read as "new report".
- Commit `d0ea97c8edf1935e8cab082d791ca7230bfb27d5` (2026-11-13 02:04:07, message: "gates.sh: crash check compares report
  names, not the count (the system pruned an old report at 02:03 and the count check stopped the re-gate after 12 prefill
  rows; no new panic/watchdog/gpuRestart file)") replaced the count check with a name-set comparison. The file on disk is
  now that fixed version, so the fix post-dates the 02:02:51 stop and cannot have prevented it.
- No new report exists. `ls -t /Library/Logs/DiagnosticReports/ | head -3` is identical at the start of every section and at
  the end of the run: `XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag`, `XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag`,
  `XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag`. All three are XeonLLM resource/disk-write `.diag` files from Nov 12 19:38–23:04.
  Newest file of any kind: `Nov 13 02:02:20` (directory mtime), newest report `Nov 12 23:04:58`. The Nemotron tensor row's own
  `.err` has no assert/error line (`grep -c GGML_ASSERT` = 0; 7 CSV rows present).

Not run because of the stop (and **not re-run**, since the stop rule says stop all work on exit 9, and the four rows
would have needed the same card-0/1 GPU):

- `card 0 LFM3-1.7B-F16`, `card 1 LFM3-1.7B-F16`
- `both cards 0,1 -sm layer Ternary-Bonsai-2-27B-PQ2_0`, `-sm tensor` (the tensor row is the expected `handled (exit 86)` refusal)
- `both cards 0,1 -sm layer Underdog-Saluki-27B-1.0-IQ2-mix`, `-sm tensor`
- `35B host (-ngl 0)` — the row the R1b rebuild (core/0086) was for. Its previous value (`out/pp-35b-host.err`, R2 first pass,
  2026-11-12 14:34, engine `d81235049` pre-0085/0086) was `rc=134 rows=6` with
  `/Users/sam/firellama/vendor/llama.cpp/ggml/src/ggml-backend.cpp:2193: GGML_ASSERT(id >= 0 && id < n_expert) failed`
  (`grep -c GGML_ASSERT out/pp-35b-host.err` = 1). This run produced no new 35B row, so the "rc=0 with 7 rows" check is
  **unverified**, not passed.

The 20-row verdict for section 3.3 is therefore: 12/20 rows pass as quoted, 8/20 **not measured**.

## proofs (section 2 lines)

Wave64 lines, quoted from `gates-proofs-b.log` (the script reads them out of `out-b/all-c{0,1}.log`):

```
card 0: ggml_metal: aligned mat-vec reads ON by amdgpu_gfx600 (override with TOSH_MV_ALIGN=1 or =0)
card 0: ggml_metal: device 0: AMD Radeon HD - FirePro D700 (peer group 0, not bridged) probed SIMD-group width = 64 (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)
card 0: ggml_metal: wave64 decode ON: quantized/f16/bf16 mat-vec on GPU (see the allowlist in ggml_metal_library_get_pipeline_mul_mv)
card 1: ggml_metal: aligned mat-vec reads ON by amdgpu_gfx600 (override with TOSH_MV_ALIGN=1 or =0)
card 1: ggml_metal: device 0: AMD Radeon HD - FirePro D700 (peer group 0, not bridged) probed SIMD-group width = 64 (32 = Apple/AMD RDNA, 64 = AMD GCN/Vega)
card 1: ggml_metal: wave64 decode ON: quantized/f16/bf16 mat-vec on GPU (see the allowlist in ggml_metal_library_get_pipeline_mul_mv)
```

Six tg128 lines:

```
X Qwen3-4B-Q4_K_M tg128 "16.711207" sd "0.009489"
X Qwen3-0.6B-Q8_0 tg128 "58.886377" sd "0.160908"
TOSH_MV_ROWS8_DISABLE Qwen3-4B-Q4_K_M tg128 "14.164909" sd "0.009280"
TOSH_MV_ROWS8_DISABLE Qwen3-0.6B-Q8_0 tg128 "58.881532" sd "0.094107"
TOSH_FULL_TG_DISABLE Qwen3-4B-Q4_K_M tg128 "16.655278" sd "0.005733"
TOSH_FULL_TG_DISABLE Qwen3-0.6B-Q8_0 tg128 "58.717888" sd "0.090090"
```

X above ROWS8_DISABLE holds for Qwen3-4B-Q4_K_M (16.711207 > 14.164909); for Qwen3-0.6B-Q8_0 the two are equal within noise
(58.886377 vs 58.881532, sd ≈ 0.09–0.16) — the 0.6B model does not move with the rows8 control. `TOSH_FULL_TG_DISABLE` is
also ≈ X for both. Those are the numbers; no claim beyond them.

## proofs8 — metal/0083 rows

Method for all four processes: shipped `llama-bench` (sha256 `63eb2a01af361672…`), engine `d81235049`, card 1
(`GGML_METAL_DEVICE_INDEX=1`), `/Users/sam/models/Qwen3-4B-Q4_K_M.gguf`, `-ngl 99 -fa 1 -ub 128 -p 512 -n 128 -d 6144 -r 3`,
arm `new` = `XEONLLM_NOOP=1`, arm `w64` = `TOSH_FA_PF_W64=1`. Rows from `out-b/p83-*.csv` (n_prompt / n_gen / avg_ts / stddev_ts):

| process | arm | pp512 (tok/s) | tg128 (tok/s) |
|---|---|---|---|
| 1 | new | **56.389557** sd 0.055252 | 12.134536 sd 0.001417 |
| 2 | new | **56.363050** sd 0.029067 | 12.134246 sd 0.006569 |
| 1 | w64 | **27.609756** sd 0.006268 | 12.140168 sd 0.002353 |
| 2 | w64 | **27.605465** sd 0.002472 | 12.135588 sd 0.000925 |

Both `new` pp512 values (56.389557, 56.363050) are above both `w64` values (27.609756, 27.605465). tg128: new 12.134536 /
12.134246 vs w64 12.140168 / 12.135588 — the two arms are the same within noise, so the "tg128 alike" expectation holds as
"no measurable difference", not as new > w64.

0083 text: `0083 text new: 'Okay, the user provided a lot of repeated sentences about a committee meeting. Let me see. The main points are that the '`
`0083 text w64: 'Okay, ...'` (same 120 chars) · `0083 text identical`. Files `out-b/t83-new.txt` and `out-b/t83-w64.txt`
(md5 `e84fe8e4c1554fb7f8653025ed3655c5`, byte-identical to the first R2's `out/t83-*.txt`).

## proofs8 — metal/0084 texts and kernels

Method: shipped `llama-server` (`63eb2a01af361672…`, engine `0.87.31-beta.8` banner in each `.log`), model
`/Users/sam/models/Qwen3.6-27B-Heretic-Uncensored-FINETUNE-NEO-CODE-Di-IMatrix-MAX-GGUF/Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf`,
`-ngl 12 -c 4096 -ub 128 -b 512 -t 12 -fa on --jinja --parallel 1 --cache-ram 0 -v`, prompt "Explain what a binary search tree is.",
`max_tokens 64`, `temperature 0.0`, `seed 1`. one12: `GGML_METAL_DEVICE_INDEX=1`; two12: `GGML_METAL_DEVICE_LIST=0,1 --split-mode layer`;
control two12-multi: same plus `TOSH_GDN_STATE_FUSION_MULTI=1`.

First 120 chars of each text (from `out/t84-*.txt`; `out-b/t84-*.txt` are byte-identical, md5 `236a5fc1e5aea56f7990f6963f2376e7` for one12 and two12):

- `t84-one12.txt`: `Here's a thinking process:\n\n1.  **Understand User Request:** The user wants an explanation of what a binary search tree`
- `t84-two12.txt`: `Here's a thinking process:\n\n1.  **Understand User Request:** The user wants an explanation of what a binary search tree`
- `t84-two12-multi.txt` (control): `Here000000000000000000000000000000000000000000000000000000000000000|` (68 bytes, md5 `b204e904c01cfd44f9e59cdd987456b3`)

`0084 twocard12 identical to one12`; `0084 control differs (expected)` (with `/Users/.../out-b/t84-one12.txt /Users/.../out-b/t84-two12-multi.txt differ: char 5, line 1`
from `cmp` in the log). Kernel lines, from `gates-proofs8-b.log`:

```
kernels one12: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1 
kernels two12: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0 
kernels two12-multi: gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1 
```

one12 shows `rows=1_fold=1`, two12 only `rows=0_fold=0`, control `rows=1_fold=1`.

## repro — metal/0085 proof

Method: `repro.sh ship` unchanged. Shipped `llama-server` (`63eb2a01af361672…`), engine banner `0.87.31-beta.8` in the log,
model `/Users/sam/models/Qwen3-14B-Q4_K_M.gguf`, both cards (`GGML_METAL_DEVICE_LIST=0,1`, layer split), `-ngl 99 -c 32768 -t 10 -fa auto
--jinja --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode layer`, `TOSH_FA_AMD=1`, one ~5.4k-token prompt, `max_tokens 64`,
`temperature 0.0`. Log: `out/repro-ship.log` (written by `repro.sh`'s default `LOGDIR=out`, not `out-b`; `gates-repro-b.log`
quotes the summary line from it).

`ship: 200 448.1 b'{"choices":[{"finish_reason":"length","index":0,"message":{"role":"assistant","content":"","reasoning_conten timeouts=0 text ok 'Okay, the user asked why the sky is blue and then repeated a'`
`out/repro-ship.out`: `200 448.1 ...` / `text ok 'Okay, the user asked why the sky is blue and then repeated a'`.

Prompt eval and eval timing, from `out/repro-ship.log`:

```
7.51.890.557 I slot print_timing: id  0 | task 0 | prompt eval time =  429547.66 ms /  5430 tokens (   79.11 ms per token,    12.64 tokens per second)
7.51.890.567 I slot print_timing: id  0 | task 0 |        eval time =   18443.59 ms /    64 tokens (  292.76 ms per token,     3.42 tokens per second)
7.51.890.568 I slot print_timing: id  0 | task 0 |       total time =  447991.26 ms /  5494 tokens
7.51.890.569 I slot print_timing: id  0 | task 0 |    graphs reused =         63
```

Decode is **292.76 ms/token**, in the "near 290" band the pass criteria ask for (the pre-0085 first R2 was `out/repro-ship.log`
from Nov 12 15:47, a different run; the A/B in `out/repro-ab/` had b8 decode 0.49 tok/s and b7 3.33–3.38 tok/s, i.e. ~2000 ms/token —
different prompt, not quoted as the same row). This run's `448.1 s` wall matches `total time = 447991.26 ms`.

## Method line for every throughput number

- Shipped engine: `dist/XeonLLM.app/Contents/Resources/bin/llama-server`, sha256 prefix **`63eb2a01af361672`**
  (identity: `shasum -a 256` = `63eb2a01af361672`, `assert[bundle]: sha256 63eb2a01af3616727827eb7bcdf90acf5b4919658cced1251575a4f8190c2221`), engine commit
  `d81235049` (build 11429), VERSION `0.87.31-beta.8`, banner `XeonLLM engine 0.87.31-beta.8 (app standalone)`.
- Hardware: 2017 Mac Pro, Intel Xeon E5-2697 v2 (12 cores / 24 threads), 2 × AMD FirePro D700 (MTL0 = card 0, display; MTL1 = card 1),
  macOS 15.8 (24H23). Every number below was taken serially: one section at a time, one GPU program at a time, nothing else heavy running.
- tg128 (proofs): `llama-bench` sha `93db3d0cd285ec50`, card 1 (`GGML_METAL_DEVICE_INDEX=1`), Qwen3-4B-Q4_K_M and Qwen3-0.6B-Q8_0,
  `-ngl 99 -p 0 -n 128 -r 5 -fa 1`, env `X` / `TOSH_MV_ROWS8_DISABLE=1` / `TOSH_FULL_TG_DISABLE=1`.
- pp512 / tg128 (0083): same `llama-bench`, card 1, Qwen3-4B-Q4_K_M, `-ngl 99 -fa 1 -ub 128 -p 512 -n 128 -d 6144 -r 3`, 2 processes per arm.
- prefill rows: same `llama-bench`, `-ngl 99 -fa 1 -p 16,128,256,448,512,1024,2048 -n 0 -r 1`, one card per row unless the model is ≥ 5905580032 bytes (both cards, `-sm layer` / `-sm tensor`).
- repro: engine above, both cards, model/method as in the repro section.

## DiagnosticReports before and after

- Before the first section (`gates-identity-b.log` line 1, 00:48:07) and after the last (`gates-repro-b.log`, 02:46:23), and at the start/end of every section in between:
  `XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag`.
- Outside the script: `ls -t /Library/Logs/DiagnosticReports/ | head -3` run by hand before the first section (00:47) and after the last (02:49, 02:52) gave the same three names. No `panic`/`watchdog`/`gpuRestart` file was created or modified during the run; the count stayed 20 throughout (checked at 02:06, 02:49, 02:52).

## Deviations and skipped work

- **prefill**: stopped at row 12/20 by the count-based `chk` after the OS pruned three old reports. `gates.sh` was not edited, not worked around with my own GPU commands, and the remaining 8 rows were not run. Commit `d0ea97c` (outside this session's tool calls, per its timestamp and message) changed `chk` to compare names afterwards; the on-disk `gates.sh` is that version, so a re-run now would use the name check. `out-b/` still holds only the 12 rows plus the earlier 10 from the first R2 that `out/` keeps.
- `proofs` X-vs-ROWS8 for Qwen3-0.6B-Q8_0: no separation (see the numbers). Not a gate line in the brief beyond "X should be above ROWS8_DISABLE"; quoted as measured.
- Nothing else skipped. The first R2's `preflight`/`engine`/`proofs`/`proofs8`/`avx`/`repro` numbers in `out/` are from 2026-11-12 14:48–16:27, i.e. before the R1b binaries (R1b commit `7241240`, 00:47:13); this report does not reuse them except where a row was explicitly not re-measured (35B host `.err`, and the `t84-*.txt` in `out/`, which are byte-identical to this run's `out-b/t84-*.txt`).

## Bottom line

- identity, ops, coverage, preflight, engine, proofs, proofs8, avx, repro: pass on the R1b binaries (`63eb2a01af361672`, `0.87.31-beta.8`, engine `d81235049`, patches incl. metal/0085 and core/0086).
- prefill: 12 of 20 rows pass; 8 rows (LFM3 both cards, Ternary-Bonsai layer+tensor, Underdog-Saluki layer+tensor, **35B host**) not measured. The 35B-host regression the rebuild targeted is therefore still open on the gate sheet.
- No new crash/panic/watchdog/gpuRestart report; the one stop line is a false positive from the wrapper's count check, with the OS report pruning as the cause.
## Correction to the prefill section (added after the first write)

The prefill stop was not a crash, and the `chk` that stopped it was not the version on disk at the time.
`gates.sh` mtime is `Nov 13 02:03:58`; its committed blob (commit `d0ea97c`, 02:04:07, "gates.sh: crash check
compares report names, not the count (the system pruned an old report at 02:03 and the count check stopped the
re-gate after 12 prefill rows; no new panic/watchdog/gpuRestart file)") already contains the name-based `chk`:

```
CRL=$(mktemp); ls /Library/Logs/DiagnosticReports/ | grep -E 'panic|watchdog|gpuRestart' | sort > $CRL
chk() { local new; new=$(ls ... | sort | comm -13 $CRL -); if [ -n "$new" ]; then ... exit 9; fi }
```

A `comm -13` on the *pruned* list cannot print names either. The only `exit 9` left that prints those three names is
a `chk` comparing counts, which is the **older** version of the script. The prefill section was therefore started with
the old `gates.sh` in memory, before 02:03:58; `gates-prefill-b.log` (mtime 02:02:51) predates both the file write and
the commit. I did not edit `gates.sh`, `srv.sh` or `repro.sh` (all three are identical to HEAD: `git status --porcelain`
on them is empty; `gates.sh` hash `798bc62948b320c4d03a9abb5174dd802749fe3b`). The false stop stands as reported:
no new report (top-3 unchanged, count 20 at 02:06 / 02:49 / 02:52), 12 rows pass, 8 rows not measured.
