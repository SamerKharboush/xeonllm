# Step 3 - Ternary-Bonsai-2-27B-PQ2_0 band300 text differs beta.7 vs beta 8

Worktree `/Users/sam/Library/Caches/xeonllm-wt-fa` (series 0001-0086 on pin `d81235049`), build dir `build-fa`.
Model `/Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf`, all runs `-ngl 0` via `scripts/stress-release.sh`
(`MODES=ngl0`), 12 threads.

## 1. Label table

`vs` columns: cell text compared against the beta.7 gate reference
(`gates-beta7/out2/set/`) and the beta 8 gate reference (`gates-beta8/out/set/`).
Every run PASS (rc 0). `band16`/`band1100` values omitted where the cell was not run;
`MISSING` in `cmp.py` means "cell not run in this label".

| label | patch state (worktree vs series HEAD) | llama-server sha | band300 len | vs beta.7 | vs beta 8 |
|---|---|---|---|---|---|
| b7 | beta.7 gate engine, unmodified | `1a68d3efcbf476e7` | 274 | - (ref) | diff@226 |
| r86 | core/0086 reverted | `61626275a7ff4c39` | 276 | diff@226 | IDENTICAL |
| r82r86 | core/0082 + core/0086 reverted | `f01bb3615432c450` | 276 | diff@226 | IDENTICAL |
| r85 | metal/0085 reverted | `7f704be525ede661` | 276 | diff@226 | IDENTICAL |
| r84 | metal/0084 reverted | `fe4404b87d211bf3` | 276 | diff@226 | IDENTICAL |
| r8583 | metal/0085 + metal/0083 reverted | `49b378a6b2c75bcb` | 276 | diff@226 | IDENTICAL |
| rmetal | whole `ggml/src/ggml-metal/` reverted (36 files) | `67a9aee0b9e86339` | 276 | diff@226 | IDENTICAL |
| envoff | dist beta 8 binary + `GGML_OP_OFFLOAD_MIN_BATCH=100000` | `63eb2a01af361672` | 276 | diff@226 | IDENTICAL |
| final | series HEAD, worktree clean | `53546683d2539c54` | (not re-run) | - | - |

`llama-quant.cpp` was also reverted alone: the relink produced a byte-identical binary
(`53546683d2539c54`), i.e. `llama-quant.cpp` is not linked into `llama-server` - it cannot
affect inference. Diff saved as `quant.diff`.

Reference texts (`gates-beta7/out2` vs `gates-beta8`):

| cell | beta.7 len | beta 8 len | identical | first difference |
|---|---|---|---|---|
| band16 | 309 | 309 | yes | - |
| band300 | 274 | 276 | no | char 226: `Likely blue.` vs `Likely "blue".` |
| band1100 | 255 | 255 | yes | - |

## 2. What the bisect cleared

Reverted with `git apply -R` (worktree only, never committed):

- `core/0086` (`r86`) - band300 still beta 8
- `core/0082` + `core/0086` together (`r82r86`) - still beta 8. Both 0082 hunks go with it:
  the `src/llama-context.cpp` `sched_reserve` compute-buffer cap, and the
  `ggml/src/ggml-backend.cpp` `src_type`/`src_on_host` block.
- `metal/0085`, `metal/0084`, `metal/0085`+`metal/0083` - still beta 8
- whole `ggml/src/ggml-metal/` (36 files, `rmetal`) - still beta 8
- `src/llama-quant.cpp` - not in the binary at all

`envoff` rules out the op-offload mechanism directly: the beta 8 dist binary with
`GGML_OP_OFFLOAD_MIN_BATCH=100000` (op offload effectively off, no rebuild) still emits
beta 8's text. So the difference is not "which backend computes the prefill batch".

Conclusion: the culprit is inside the series squash `731b358fd` ("series", 183 files,
54k insertions), outside `ggml/src/ggml-metal/` and outside the files listed above.
It was **not** isolated to a hunk inside the window. See 2b: `ggml/` cannot be reverted to
the pin at all, because `GGML_TYPE_PQ2_0` (the type this file is stored in) is introduced by
the same squash, and the series code that consumes it does not compile without it. Isolating
the hunk needs a PQ2_0-preserving partial revert (pin `ggml/` + series PQ2_0 files), which is
a new patch, not a revert.

## 2b. Why the bisect cannot reach the pin

The pin `d81235049` does not know the type this file is stored in:

```
pin  ggml/include/ggml.h   PQ2_0 refs: 0     HEAD: 2
pin  ggml/src/ggml-common.h block_pq2_0: 0    HEAD: 2
```

`GGML_TYPE_PQ2_0`, `block_pq2_0`, `dequantize_row_pq2_0` are introduced by `731b358fd`.
So `ggml/` cannot be reverted to the pin while this GGUF loads - reverting the numeric core
fails to compile against the series code that still references it
(`ggml.c` `GGML_OP_COUNT` static assert, `ggml-backend.cpp` `read_batch_begin`,
`src/llama-context.cpp` `ggml_backend_sched_share_compute_buffers`,
`src/models/delta-net-base.cpp` `ggml_gated_delta_net_set_raw_gates`). The beta.7 gate
binary is therefore not built from this pin either; it is a sibling branch that already has
PQ2_0. Any pin-based bisect of `ggml/` is invalid for this model.

Leading un-reverted candidate, by file:line:

- `ggml/src/ggml-quants.c:494` `dequantize_row_pq2_0` - the model's own codec
- `ggml/src/ggml-common.h:199-200` `QK_PQ2_0 128`, one fp16 scale per 128 weights
- `ggml/src/ggml-cpu/` vec-dot / mul-mat paths for `GGML_TYPE_PQ2_0`

A delta here is tiny (fp16 scale, different sum order) and content dependent, which is what
one near-tie flip at `band300` and clean `band16`/`band1100` look like.

## 3. Verdict

**No correctness bug demonstrated; the change looks like a benign numeric tie-break.**

- `band16` (309 chars) and `band1100` (255 chars) are byte-identical between beta.7 and
  beta 8. Only `band300` differs, and only by one token at char 226: `Likely blue.` vs
  `Likely "blue".`. Same word, same intent, different punctuation token - the signature of
  two near-tied logits being cut differently, not of a broken kernel.
- A real kernel/quant bug would move text at every prompt length, including the 125-token
  `band16` prompt and the long `band1100` prompt.
- Op offload (the mechanism the 0082 hunk was about) is ruled out by `envoff`.
- Reverting any single patch in the series never reproduced beta.7's text, so the flip comes
  from the squash bulk (most plausibly the CPU numeric core: `ggml/src/ggml-cpu`,
  `ggml/src/ggml-quants.c`, turbo-quant dot paths), which is exactly where the remaining
  un-reverted files sit.

Caveat worth recording: the earlier `no82be` data point in this ticket (claimed "all three
IDENTICAL to beta.7" with only 0082's backend hunk reverted, sha `84dd82a51a57aec7`) does not
reproduce. That run came from the period when the worktree was at a mixed state (patch apply
failures against already-applied series commits, a stray `tests/test-sched-offload.cpp`).
Every run in this report is from a verified-clean tree with a recorded sha, and the
equivalent revert here (`r82r86`, a superset of `no82be`) still gives beta 8's text.

## 4. Hygiene

`git -C /Users/sam/Library/Caches/xeonllm-wt-fa status --short` (final):

```
```

Final `build-fa/bin/llama-server` sha:

```
53546683d2539c54...
```

DiagnosticReports: `diagrep-00-initial.txt` captured before the first run;
`diagrep-04-final.txt` after the last. `comm -13` of the two: no new entries
(no `panic`, `watchdog` or `gpuRestart`).

Saved artifacts in this directory: `r86.diff`, `r82r86.diff`, `r85.diff`, `r84.diff`,
`r8583.diff`, `metal.diff`, `cpucore.diff`, `ggmlinc.diff`, `ggmlsrc.diff`, `backend.diff`,
`ggmlall.diff`, `quant.diff`, `squash-files.diff`, `restore.diff`, `cmp.py`, `compare.txt`,
`diagrep-0*.txt`, plus per-label `*.nohup` and `<label>/tables/stress.tsv`.