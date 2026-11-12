# 24: two-card 32k answers at signs - rate and log diff

Date: 2026-11-12. Worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`, HEAD `1a34d4723`
("core/0086 (ticket 22)"), pin `d81235049`. Tree clean before and after (`git status --short` empty).

## Binary

`cmake --build build-fa -j8 --target llama-server` (`build.log`), no GPU program during the build.
`shasum -a 256 build-fa/bin/llama-server` prefix `53546683d2539c54`.

The app binary used by `repro.sh` when `B` is not set is
`/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin/llama-server` (shipped beta 8,
`4f72303829f6fdda`); every run below sets `B` to the worktree build (log line
`XeonLLM engine unknown (app standalone)` = this build; beta.7 logs print `0.87.31-beta.7`).

## Log diffs (step 2)

`logdiff-b7good-b7bad.txt`: `gates-beta7/out/repro-ship.log` (beta.7, good) vs
`gates-beta8/out/repro-ab/repro-b7-1.log` (beta.7, bad). After stripping timestamps the only
differences are the port, the two per-512-token timing lines, the two `ggml_metal` "one node of a
512-token batch averages ... ms" warnings (order MTL0/MTL1 swapped, values 50.2/50.7 vs 54.9/50.5)
and the eval times. No buffer-size, free-memory, op-offload or graph-split line differs.

`logdiff-b7bad-b7bad.txt`: b7-1 vs b7-2 (both bad): same, only port/timings/warning order.

`logdiff-new2-new1.txt`: `evidence/23/repro/repro-new-2.log` (good) vs `repro-new-1.log` (bad):
same, plus the bad run prints two teardown warnings that the good run does not:

```
W ~llama_context: MTL0_Private compute buffer size of 582.0547 MiB, does not match expectation of 438.4609 MiB
W ~llama_context: MTL1_Private compute buffer size of 492.0391 MiB, does not match expectation of 348.4650 MiB
```

### What the logs do not contain

The 14B server at `-lv 3` prints no `compute buffer size` at load, no
`recommendedMaxWorkingSetSize`, no `op offload` line, and no graph split line. Those lines need
`-v`/`-lv 4` (ticket 23: `evidence/23/RESULT.md`, "Compute buffer lines"). The `grep` counts are
in the diff files: 0 occurrences of `recommendedMaxWorkingSetSize`, `op offload`, `graph .* splits`
in every log. `grep -c "does not match"` = 1 in `repro-new-1.log`, 0 in the others (b7-1, b7-2,
new-2, b8-1, b8-2).

The teardown line is the `llama_context` destructor size check
(`src/llama-context.cpp:645-653`), i.e. the allocator grew past the worst-case reservation during
the run; ticket 23 shows the same growth for a mixed-route (decomposed then FA) request and calls
it a reserve artifact, not a failure.

## Rate (step 3)

`B=build-fa/bin`, `LOGDIR=evidence/24/rate`, `evidence/gates-beta8/repro.sh` verbatim, one at a
time, each wrapped in `perl -e 'alarm 1800; exec @ARGV'` (`rate.sh`, `rate-run.log`). Labels
interleaved d,u,d,u,... then the remaining d. `rate/repro-<label>.log`, `.out`; table in
`rate-table.txt` (`table.py` output). Times are `repro.sh` wall clock; prompt/eval are the
`slot print_timing` lines.

| label | status | secs | prompt | eval | TEXT line |
|---|---|---|---|---|---|
| d1 | 200 | 448.5 | 12.63 tok/s | 293.48 ms/tok | text ok |
| u1 | 200 | 258.5 | 22.61 tok/s | 290.74 ms/tok | text ok |
| d2 | 200 | 447.9 | 12.65 tok/s | 292.96 ms/tok | text ok |
| u2 | 200 | 258.5 | 22.62 tok/s | 290.84 ms/tok | text ok |
| d3 | 200 | 448.2 | 12.64 tok/s | 293.29 ms/tok | text ok |
| u3 | 200 | 258.5 | 22.60 tok/s | 289.70 ms/tok | text ok |
| d4 | 200 | 448.3 | 12.63 tok/s | 292.03 ms/tok | text ok |
| u4 | 200 | 258.4 | 22.62 tok/s | 290.80 ms/tok | text ok |
| d5 | 200 | 448.2 | 12.63 tok/s | 291.78 ms/tok | text ok |
| d6 | 200 | 448.6 | 12.62 tok/s | 292.91 ms/tok | text ok |

Bad count: **0 of 10** (6 default ub, 4 ubatch 128). Every `d` run logged the two
`ggml_metal_op_flash_attn_ext: ... tile kernel takes the prefill` lines (mixed route: decomposed
first ~3.2k tokens, then FA); no `u` run did (all-decomposed at ub 128). `grep -ci` for
`nan`, `failed`, `evict`, `overcommit` = 0 and `does not match` = 0 in all ten logs. No `Timeout`
lines. The whole arm matches the ticket-23 repro2 "new" numbers (12.62-12.65 tok/s prompt, 3.41
tok/s decode at default ub; 22.60-22.62 at ub 128), so the repro reproduces the launch shape, not
the bug.

## Step 4 (fallback: beta.7, no TEXT BAD in step 3)

No TEXT BAD in the 10 rate runs, so per the brief the c/w arms were not run; instead 4 default-ub
runs with the beta.7 engine (`evidence/gates-beta8/beta7-bin`, `LOGDIR=evidence/24/beta7`,
`beta7-run.log`, table `beta7-table.txt`). Each run logs
`XeonLLM engine 0.87.31-beta.7 (app standalone)`, i.e. the right binary.

| label | status | secs | prompt | eval | TEXT line |
|---|---|---|---|---|---|
| b1 | 200 | 336.2 | 17.09 tok/s | 293.33 ms/tok | text ok |
| b2 | 200 | 336.2 | 17.09 tok/s | 291.88 ms/tok | text ok |
| b3 | 200 | 336.2 | 17.09 tok/s | 291.77 ms/tok | text ok |
| b4 | 200 | 336.5 | 17.07 tok/s | 292.27 ms/tok | text ok |

Bad count: **0 of 4**. All four logged the two FA tile-kernel fallback warnings (beta.7 takes the
FA path), `does not match` = 0, no `nan`/`failed`/`evict`/`overcommit`, no `Timeout`.

## Extra default-ub runs (current engine)

4 more default-ub runs after the beta.7 arm (`extra.sh`, `extra-run.log`, `extra-table.txt`), to
raise the sample for "not reproducible today".

| label | status | secs | prompt | eval | TEXT line |
|---|---|---|---|---|---|
| d7 | 200 | 448.3 | 12.63 tok/s | 293.29 ms/tok | text ok |
| d8 | 200 | 448.4 | 12.63 tok/s | 294.25 ms/tok | text ok |
| d9 | 200 | 448.2 | 12.63 tok/s | 292.90 ms/tok | text ok |
| d10 | 200 | 448.1 | 12.64 tok/s | 292.03 ms/tok | text ok |

Bad count 0 of 4. `does not match` = 0, no `nan`/`failed`/`evict`.

## Totals

- Worktree build, default ub: **14 runs** (d1-d6, d7-d10), 0 TEXT BAD.
- Worktree build, ub 128: 4 runs (u1-u4), 0 TEXT BAD.
- beta.7 engine, default ub: 4 runs (b1-b4), 0 TEXT BAD.
- Combined with the ticket records (18 runs before this work: b7-1, b7-2, new-1 bad; b8-1, b8-2,
  b8w64-1, w64-1, new-2, beta.7 ship, new-3, w64-2, new-4, w64-3, new128-1, new128-2, w64128-1,
  w64128-2 good), 3 bad of 40 recorded runs across both engines; none reproduced here.

## Safety and DiagnosticReports

- `ls -t /Library/Logs/DiagnosticReports/ | head -3` before (`diagrpts-before.txt`) and after
  (`diagrpts-after.txt`). The only new entry is
  `XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag` (23:04:56), a "Microstackshots" CPU-resource
  report for the `XeonLLM` GUI app (`/Applications/XeonLLM.app`), version 0.87.31-beta.7, covering
  19:38-23:04; it is not a `*.panic`, `*watchdog*` or `*.gpuRestart` file. The number of
  panic/watchdog/gpuRestart files in the directory is 25 both before and after.
- One GPU program at a time: every run went through `repro.sh`, which kills its own server and
  waits; `pgrep -x llama-server` showed only pid 747 (untouched) between runs. No build ran while a
  GPU program was up. All server runs wrapped in `perl -e 'alarm 1800; exec @ARGV'`. `-c 32768`,
  `-ub 512`, the prompt length and the model were left exactly as the repro sets them.
- No engine code was changed; `git -C /Users/sam/Library/Caches/xeonllm-wt-fa status --short` is
  empty (nothing to clean, no temporary logs were added to the worktree).

## Artifacts (evidence/24)

- `build.log`, binary sha `53546683d2539c54`
- `logdiff-b7good-b7bad.txt`, `logdiff-b7bad-b7bad.txt`, `logdiff-new2-new1.txt`, `loggrep.txt`
- `rate/` (repro-d1..d6, u1..u4), `rate.sh`, `rate-run.log`, `rate-table.txt`, `table.py`
- `beta7/` (b1..b4), `beta7-run.log`, `beta7-table.txt`, `step4b.sh`
- `extra/` (d7..d10), `extra-run.log`, `extra-table.txt`, `extra.sh`
- `tok-at.py`, `tok-at.txt`, `iogpu-sample-b1.txt`
- `diagrpts-before.txt`, `diagrpts-after.txt`

## Findings

Not isolated. No cause found, so no code change is proposed. What was checked:

1. **Log diff (step 2).** No line separates a bad run from a good one on the same engine. The only
   difference in the whole `repro-new-1` (bad) vs `repro-new-2` (good) pair is the two
   `~llama_context` teardown warnings (582.05/492.04 MiB actual vs 438.46/348.47 expected). That is
   the allocator growing past the worst-case reservation, which ticket 23 already attributes to the
   mixed route (decomposed prefill for the first ~3.2k tokens, FA after the 256 MiB cap) - it is a
   reserve artifact, and it does not appear in the beta.7 bad runs, so it is not the failure
   signature.
2. **The answer is not the NaN-argmax signature.** `@` is token 31 in this model's own vocab
   (`tok-at.py`, `tok-at.txt`; token 0 is `!`). With NaN logits, `ggml_vec_argmax_f32`
   (`ggml/src/ggml-cpu/vec.h:1618-1626`, `max = -INFINITY` and `max = MAX(max, x[i]); if (max ==
   x[i])`) returns 0, i.e. `!`. So a pure "all logits NaN" run would print `!!!!`, not `@@@@`. A
   garbage-but-finite logits vector that happens to peak at 31 fits the text; no NaN check was in
   the binary and none was reached (`grep -ci nan` = 0 in every log).
3. **Rate (step 3): 0 bad of 10** (6 default ub, 4 ub 128), and **0 bad of 4 beta.7 runs** (step 4
   fallback), plus 4 extra default-ub runs. In total 22 runs today after 21:26, all good; the ticket's
   own 0 of 8 in `evidence/23/repro2` ran 18:36-19:26, also all good. The three recorded bad runs are
   all between 16:56 and 17:41 on 2026-11-12. The failure is rare and not tied to a route, engine or
   batch size in anything measured here.
4. **Memory.** `ioreg -c IOAccelerator` during the b1 run: 4.85 GB in use / 1.41 GB free on card 0
   and 4.85 / 1.58 GB on card 1 (`iogpu-sample-b1.txt`), i.e. the ~6.3-6.4 GB D700 working set is
   not exceeded at that instant. Only one instant per card was sampled; the peak during the
   decomposed 256 MiB KQ batches was not captured. The ticket's ~6.9 GB overcommit figure is not
   confirmed or refuted by this sample.
5. **Not run.** No `-v`/`-lv 4` 14B run, so the per-device `sched_reserve` and op-offload lines
   were not captured. No NaN check on the final logits, because no bad run occurred while the
   instrumented build existed (adding one costs a rebuild plus a rare event; there were 0 bad runs
   in 10 at default ub). The c/w arms (`--cache-ram 0`, `TOSH_FA_PF_W64=1`) were not run because
   step 3 had no TEXT BAD; the brief says to run them only on a bad arm.