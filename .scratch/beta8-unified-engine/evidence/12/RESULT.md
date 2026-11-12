# Beta 8, ticket 12 - prompt offload (core/0082) on the 35B MoE

## Method

| item | value |
|---|---|
| engine | `vendor/llama.cpp/build-static/bin`, llama.cpp pinned at `d81235049` (build log line "ggml commit: d81235049-dirty") + the whole `patches/llama/*` series (92 patches applied, `0082-core-prompt-offload-with-a-compute-buffer-cap.patch` is the last one) |
| llama-bench sha256 | `1a8385e315ae0302` (full `1a8385e315ae03024b47694a3b011f7f3f57fd5bf900cea47673fabad764c263`) |
| llama-cli sha256 | `f96866f469294a0c` (full `f96866f469294a0c612768acb6e3c165fe0160b4b05953d1be796ed56aa43c36`) |
| model | `/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf`, Q6_K, 28.5 GB, arch `qwen35moe 35B.A3B` |
| layers on GPU | none (`-ngl 0`), weights on the host |
| card | card 1: `GGML_METAL_DEVICE_INDEX=1` pins logical slot 0 (`MTL0`) to physical GPU 1, `-dev MTL0`; card = AMD FirePro D700, 6 GB, MTLGPUFamilyCommon3, wave64 |
| ctx / batch / ubatch / threads | `-c 8192 -b 512 -ub 512 -t 12` (bench: n_batch 512, n_ubatch 512, n_threads 12, flash_attn 1) |
| bench N | 3 processes per side, alternating on/off/off-on per rep; `-r 3` reps inside each process; llama-bench's own warmup prompt run is discarded by the tool (no `--no-warmup`) |
| text run | `llama-cli`, greedy (`--temp 0`), `-n 400`, `-f .../evidence/18/prompt4k.txt` (20613 B -> 4210 prompt tokens), `-s 1`, `-v`, `GGML_SCHED_DEBUG=2` |
| env | `TOSH_FA_AMD=1`, `GGML_METAL_DEVICE_INDEX=1`, `TOSH_OFFLOAD_MAX_COMPUTE_MB` unset (cap 1536 MiB) |

Build note: `scripts/build-engines.sh` builds `llama-server`, `llama-bench`, `llama-perplexity`,
`test-backend-ops` - not `llama-cli`. The shipped `llama-cli` was stale (no `op offload` string), so
`llama-cli` was built separately from the same patched tree and same cmake flags
(`cmake --build build-static --config Release -j 8 -t llama-cli`). All three binaries now contain the
`op offload` strings.

## Text run (llama-cli, 400 tokens greedy)

| run | flag | op offload log line | prompt t/s | gen t/s | `MUL_MAT_ID):` lines | of those on `[ MTL0` | `MUL_MAT):` lines | of those on `[ MTL0` | failed to allocate |
|---|---|---|---|---|---|---|---|---|---|
| text-on | (default = on) | `sched_reserve: op offload on: MTL0_Private compute buffer 307.63 MiB, cap 1536 MiB` | 43.75 | 9.71 | 3200 | 1600 | 11339 | 5460 | none |
| text-on2 (repeat of on) | (default = on) | `sched_reserve: op offload on: MTL0_Private compute buffer 307.63 MiB, cap 1536 MiB` | 43.72 | 9.6 | - | - | - | - | none |
| text-off | `--no-op-offload` | (no line: the log only fires when `cparams.op_offload` is true) | 28.22 | 9.70 | 3080 | 0 | 10948 | 0 | none |

Scheduler split headers: on = MTL0 8180 / CPU 3109, no BLAS; off = CPU 3928 / BLAS 3900, no MTL0.
With offload off the GPU does no compute at all; with it on, every host `MUL_MAT`/`MUL_MAT_ID` that the
Metal backend accepts moves to `MTL0` (BLAS/Accelerate disappears from the split list).

### Byte comparison of the generated text

Region compared: from `[Start thinking]` to `[ Prompt`, the `[ Prompt ... ]` line excluded
(`text-{on,off}.gen`, also `text-on2.gen`).

```
$ cmp text-on.gen text-off.gen
text-on.gen text-off.gen differ: char 80, line 6
```

First differing character offset: 79 (0-based). 200 characters from that offset:

on:
```
**Input Text:** A single sentence repeated many times: "The committee met on Tuesday to review the budget, the hiring plan and the schedule for the new library wing; every member spoke in turn and the
```

off:
```
The user provided a very long, repetitive text: "The committee met on Tuesday to review the budget, the hiring plan and the schedule for the new library wing; every member spoke in turn and the notes 
```

`cmp text-on.gen text-on2.gen` -> identical (byte-for-byte), so the offload-on path is deterministic;
the difference is systematic between the two paths, not run-to-run noise.

Explanation: the divergence is in *generated* tokens (the prompt echo before `[Start thinking]` is
identical), and it starts where the two paths first use a different matmul implementation: with
offload on, the batched prompt and decode `MUL_MAT`/`MUL_MAT_ID` run as Metal kernels on copies of the
host weights; with it off they run as Accelerate BLAS / CPU AVX1 kernels. Different summation order in
Q6_K gives slightly different logits, greedy decoding then picks a different near-tie token, and the
two traces separate from there. Both traces stay coherent and both end in a correct one-sentence
summary of the meeting; the on-run trace is still inside its thinking block when the 400-token limit
hits (no `[End thinking]`), the off-run trace closes thinking and starts the answer. This is a numeric
difference in the matmul path, not a wrong-answer corruption - but it is *not* byte-identical, so the
"byte-identical" bar that patch 0082 met on the dense gemma4 12B is not met on this MoE.

## Prompt speed (llama-bench, pp512, card 1, 3 processes per side, alternating)

```
model,qwen35moe 35B.A3B Q6_K, n_prompt=512, n_gen=0, n_batch=512, n_ubatch=512, n_threads=12, fa=1, ngl=0, dev=MTL0
```

| rep | no_op_offload | avg ts | stddev ts | avg ns |
|---|---|---|---|---|
| 1 | 0 (offload ON) | 46.971269 | 0.736231 | 10902081204 |
| 1 | 1 (offload OFF) | 31.767963 | 0.282831 | 16117721564 |
| 2 | 0 (offload ON) | 46.975472 | 1.019920 | 10902759997 |
| 2 | 1 (offload OFF) | 31.777389 | 0.441252 | 16114166523 |
| 3 | 0 (offload ON) | 47.031634 | 0.588373 | 10887433389 |
| 3 | 1 (offload OFF) | 31.895801 | 0.348457 | 16053555130 |

Per side, across the 3 processes:

| side | values (ts) | mean | sd | range |
|---|---|---|---|---|
| offload ON | 46.9713, 46.9755, 47.0316 | 46.9928 | 0.0275 | 46.971 - 47.032 |
| offload OFF | 31.7680, 31.7774, 31.8958 | 31.8137 | 0.0582 | 31.768 - 31.896 |

The two process ranges do not overlap (gap 46.971 - 31.896 = 15.075 ts).
The llama-cli prompt rate agrees: 43.75 ts on vs 28.22 ts off.

llama-bench accepted `-dev MTL0`; it was used, together with `GGML_METAL_DEVICE_INDEX=1`.
`llama-bench` installs a null log callback, so no `op offload` line appears in `bench.err`; the
offload state of the bench runs is the `-nopo` column of the CSV itself (`no_op_offload` 0 = on).

## Verdict

Offload **pays** on the 35B MoE and does not corrupt the output, but it is **not byte-identical**:
pp512 46.99 +/- 0.03 ts/s with offload vs 31.81 +/- 0.06 ts/s without (ranges disjoint, 15.08 ts/s
apart), while the generated text diverges at char 79 of the thinking block (Metal vs Accelerate BLAS
summation order on Q6_K changes a near-tie greedy pick; the on-path is deterministic across two runs,
`on` == `on2` byte-for-byte).

## Notes / limits

- `llama-bench` prints no `op offload` line (null log callback); the offload state of the bench runs
  is only visible in the CSV `no_op_offload` column.
- The off run prints no `op offload` line either, because patch 0082 logs only when
  `cparams.op_offload` is true. The evidence that offload was really off in that run is the
  scheduler trace: 0 `MUL_MAT_ID):`/`MUL_MAT):` lines on `[ MTL0`, and split headers CPU+BLAS only.
- Raw node counts differ between the two runs (3200 vs 3080 `MUL_MAT_ID):` prints, 11339 vs 10948
  `MUL_MAT):` prints, 11289 vs 7828 split headers) because the Metal path splits the graph
  differently; the MTL0 counts above are the comparable numbers.
- No `failed to allocate` line in any run.
- `build.log` for this ticket is 131 MB (the whole `build-engines.sh`, all three engines).
- `monitor.log` (written by the session watchdog, not by this ticket) logs "VIOLATION: 2 GPU programs at
  once" for each `llama-cli`/`llama-bench` run and "4 GPU programs at once" during the build. Each of
  those windows held exactly one GPU program: the `perl -e 'alarm 1800; exec @ARGV'` wrapper plus its
  exec'd child, and during the build the Metal shader compiler (`xcrun metal`) that `build-engines.sh`
  runs as part of the engine build. No two GPU programs of this ticket ever overlapped.
- DiagnosticReports: newest file was `codesign_2026-11-11-211515_Sams-Mac-Pro.diag` before the build
  and after the last bench run - unchanged. No new `*.panic`, `*watchdog*` or `*.gpuRestart` file
  appeared (the newest panic, `Kernel-2026-11-11-083524.panic`, predates this session).

## Files

- `build.log` - full `build-engines.sh` output (llama + whisper + image engines)
- `text-on.out/.err`, `text-on2.out/.err`, `text-off.out/.err` - llama-cli runs
- `text-on.gen`, `text-on2.gen`, `text-off.gen` - the compared `[Start thinking]` .. `[ Prompt` regions
- `bench.csv`, `bench.err` - llama-bench pp512, 6 rows
