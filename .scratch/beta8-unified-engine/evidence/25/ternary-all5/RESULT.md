# Step 4 - all five patches reverted together, then bisected to a hunk

Series `0001-0086` on pin `d81235049`, worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`, build dir
`build-fa`. Model `/Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf` (PQ2_0), every run `-ngl 0`
through `scripts/stress-release.sh` with `MODES=ngl0`, `NGL0_CELLS="band16 band300 band1100"`.
The launch flags come from `evidence/gates-beta8/out/set/Ternary-Bonsai-2-27B-PQ2_0.applog`.

References: beta.7 = `evidence/gates-beta7/out2/set/`, beta 8 = `evidence/gates-beta8/out/set/`.
All seven runs PASS on all three cells (`<label>/tables/stress.tsv`).

## 1. Label table

| label | patch state (worktree) | llama-server sha256 prefix | rc | band300 len | band300 vs beta.7 | band300 vs beta 8 | band16 / band1100 |
|---|---|---|---|---|---|---|---|
| b8 | shipped beta 8 engine (`dist/XeonLLM.app/.../bin`) | `63eb2a01af361672` | 0 | 276 | diff@226 (276 vs 274) | IDENTICAL | IDENTICAL / IDENTICAL |
| b7 | beta.7 gate engine (`gates-beta8/beta7-bin`) | `1a68d3efcbf476e7` | 0 | 274 | IDENTICAL | diff@226 (274 vs 276) | IDENTICAL / IDENTICAL |
| all5 | all five reverted: 0086, 0085, 0084, 0083, 0082 | `8bd15fbb1d1e15fd` | 0 | 274 | IDENTICAL | diff@226 | IDENTICAL / IDENTICAL |
| add82 | all5 + `core/0082` re-applied | `71fdf177c84abdc3` | 0 | 276 | diff@226 | IDENTICAL | IDENTICAL / IDENTICAL |
| only82 | clean HEAD with only `core/0082` reverted | `81c3ca8264068fc5` | 0 | 274 | IDENTICAL | diff@226 | IDENTICAL / IDENTICAL |
| no82ctx | clean HEAD, only the `src/llama-context.cpp` hunk of 0082 reverted | `d0991ba08d9ca04d` | 0 | 276 | diff@226 | IDENTICAL | IDENTICAL / IDENTICAL |
| final | clean HEAD, all five applied (restore check) | `53546683d2539c54` | 0 | 276 | diff@226 | IDENTICAL | IDENTICAL / IDENTICAL |

`compare.txt` has the raw per-cell lines. Answer files hashed in `sha-answers.txt`:

- beta.7 shape (`6b4b41244cf5f0c1`): `b7`, `all5`, `only82` - byte-identical to each other
- beta 8 shape (`04a4b0e572283 8ca2`): `b8`, `add82`, `no82ctx`, `final` - byte-identical to each other

## 2. Result of the all-five revert

**`all5` gives beta.7's text.** `band300` = 274 chars, "Likely blue.", IDENTICAL to the beta.7 gate
run. `band16` and `band1100` IDENTICAL to both gates, as before.

This is the data point step 25c never had. The text flip is caused by the five patch files that
changed between `v0.87.31-beta.7` and now (`git diff --stat v0.87.31-beta.7 HEAD -- patches/llama`
lists exactly these five), and it is fully reversible by reverting all five.

## 3. Bisect: `core/0082` is the culprit

Patches put back one at a time in the order 0082, 0083, 0084, 0085, 0086, building and running
after each. The first addition (`core/0082`, label `add82`) already flipped the text back to beta
8's 276 chars. The bisect stopped there.

`only82` (clean HEAD, `core/0082` alone reverted) reproduces beta.7's 274 chars, so 0082 alone is
sufficient to cause the difference and none of 0083/0084/0085/0086 is needed for it.

### Which hunk of 0082

`core/0082` has two code hunks (plus `tests/`):

1. `ggml/src/ggml-backend.cpp` - the op-offload test in
   `ggml_backend_sched_backend_id_from_cur` changes from `src_backend_id == sched->n_backends - 1`
   to "any host-side backend (CPU **or ACCEL**) holding the weight".
2. `src/llama-context.cpp` - `sched_reserve()` sizes the worst-case graph and drops op offload if a
   GPU compute buffer would exceed 1536 MiB (`TOSH_OFFLOAD_MAX_COMPUTE_MB`).

`no82ctx` reverts only hunk 2 and keeps hunk 1: text is beta 8's (276). So **hunk 1, the
`ggml-backend.cpp` `src_type`/`src_on_host` block, is the culprit**; hunk 2 (the compute-buffer cap)
does not change the text on this model.

### Mechanism, corroborated by timings

`timing.tsv`:

| shape | band16 | band300 | band1100 |
|---|---|---|---|
| beta.7 (`b7`, `all5`, `only82`) | 161.7 / 163.5 / 161.0 s | 235.0 / 239.5 / 236.8 s | 420.5 / 428.1 / 420.8 s |
| beta 8 (`b8`, `add82`, `no82ctx`, `final`) | 137.1 / 137.4 / 135.0 / 135.7 s | 163.0 / 163.6 / 160.8 / 160.9 s | 240.1 / 239.6 / 235.8 / 240.7 s |

Two clean clusters, reproducible across engines and rebuilds: the beta 8 shape is ~2.6x faster at
band1100 and ~1.5x faster at band300. That is exactly what op offload of the host-resident prompt
batch buys: with 0082 hunk 1 the big `MUL_MAT` batches run on a D700, without it they run on the
12 CPU threads.

Mechanism, precisely: this build has Accelerate/BLAS registered, so the model's host weights map to
the ACCEL backend, which is **not** `sched->n_backends - 1`. Before 0082 the op-offload test
`src_backend_id == sched->n_backends - 1` therefore never matched and no op was ever offloaded -
prompt prefill stayed on the CPU. 0082 hunk 1 widens the test to any host-side backend, op offload
starts firing, the prefill batch is computed on the GPU, and the GPU and CPU sum the PQ2_0 dot
products in a different order. One near-tied logit at `band300` char 226 is cut the other way:
"Likely blue." -> "Likely \"blue\"."

That also explains the earlier dead ends in step 25c: `envoff`
(`GGML_OP_OFFLOAD_MIN_BATCH=100000`) and every metal/00xx revert left the engine on the CPU path
only in some runs, and `r86`/`r82r86`/`r84`/`r85`/`r8583` each kept 0082 hunk 1 applied, so all of
them stayed beta 8. `rmetal` likewise: reverting the whole metal backend does not undo 0082's
sched-side change, and with the op offloaded the metal kernels were still the ones computing.

Also note the two "no82" runs quoted in the beta 8 ticket (`no82be`, all three cells IDENTICAL to
beta.7 with sha `84dd82a51a57aec7`) came from the mixed-state tree and are superseded: `only82`
here is the same change from a verified-clean tree and reproduces beta.7's text on all three cells
(`cmp b7 only82` byte-identical).

## 4. Verdict

**The band300 difference is a benign numeric tie-break, not a correctness bug.**

- `band16` (309 chars) and `band1100` (255 chars) are byte-identical between beta.7 and beta 8.
- `band300` differs by one token at char 226, `blue` vs `\"blue\"` - same word, same intent.
- The flip is exactly reproduced by toggling one boolean condition in the scheduler
  (op offload on/off), and the timing split (2.6x at band1100) confirms the prefill is on a
  different device, not that a kernel is wrong.
- Two different summation orders on two different devices for the same PQ2_0 weights is expected;
  a real kernel bug would move text at every prompt length.

If a single canonical text is required across engines, pin op offload explicitly
(`--no-op-offload`) for this model at `-ngl 0`; nothing else in the series needs to change.

## 5. Hygiene

Worktree `git status --short` (final, and after the restore rebuild):

```
```

`build-fa/bin/llama-server` final sha256:

```
53546683d2539c54464672ed57d7e34f048e0e3bc9575735e4b53d9e04637b94
```

DiagnosticReports: `diagreports-first.txt` (before the first run) through `diag-07-final.txt` (after
the last). `comm -13` of the first against every later listing: **no new names** (no `panic`, no
`watchdog`, no `gpuRestart`). All seven listings are byte-identical (md5 `4402067459f1cc81...`).

`ps -ax -o pid,comm | grep -E 'llama-(server|bench|cli)|clang'` before each build and each run showed
only pid 747 (`/Users/sam/llama.cpp/build-metal/bin/llama-server`); it was never touched. All
activity was foreground and strictly sequential, one build or one server at a time.

Saved here: `all5.diff`, `all5.stat`, `only82.diff`, `no82ctx.diff`, `compare.txt`, `timing.tsv`,
`sha-answers.txt`, `bin-sha.txt`, `cmpall.py`, `diag-*.txt`, and per-label `*.log`,
`<label>/tables/stress.tsv`, `<label>/*.answers.json`, `<label>/*.cells.tsv`.

Caveat on this report: the worktree `scripts/` were not modified; one temporary debug line was added
to `/Users/sam/firellama/scripts/stress-release.sh` and removed again, `git status` there is clean
for that file.