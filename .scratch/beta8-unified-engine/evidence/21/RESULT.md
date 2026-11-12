# Ticket 21 - AMD FA prefill block on 64-lane GPUs (card 1)

**Status: complete. All four gates ran; nothing was skipped.**

## Change under test

`src/llama-graph.cpp`, `llm_graph_context::build_attn_mha`, the `amd_prefill_fa_blocked` gate:

- the block now applies on 32-lane GPUs only (unchanged there),
- on 64-lane GPUs the block is off by default, so prompt batches take the decomposed route,
- `TOSH_FA_PF_W64=1` puts the block back on 64-lane GPUs (old rule, one binary A/B),
- `TOSH_FA_PF_DISABLE` keeps working as before (it still switches the block off, and it also
  still switches the Metal-side PF kernel off in `ggml/src/ggml-metal/ggml-metal-ops.cpp`).

The diff is **uncommitted** in the worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`
(`git status --short` shows only `src/llama-graph.cpp`).

## Method

- Source: worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`, detached at `6a40e47b1`
  ("series 0001-0082 (base for ticket 21)"), i.e. the XeonLLM fork's full 82-patch series on
  upstream pin `d81235049`, **plus this uncommitted change**.
- Build: `build-fa`, `Release`, `BUILD_SHARED_LIBS=OFF`, `GGML_METAL=ON`,
  `GGML_METAL_EMBED_LIBRARY=ON`, `TOSH_ENABLE_DYNAMIC_MOE=ON`, `GGML_NATIVE=OFF`,
  `GGML_AVX2=OFF`, `GGML_FMA=OFF`, `GGML_AVX512=OFF` (flags exactly as specified).
  Targets built: `llama-bench`, `llama-cli`, `test-backend-ops`.
- `build-fa/bin/llama-bench` sha256 `ca187698a5d10fb5eabd3db08aa9e4d00ab7c8bdf63e78fd0e641868d36210e8`
  (prefix `ca187698a5d10fb5`); `build-fa/bin/llama-cli` sha256
  `c6fb501a09cb52f16d5f0d6aecd935eb1426b5b9fd5ebeddc01005c9f61dfee1` (prefix `c6fb501a09cb52f1`).
  CSV rows report `build_commit` = `6a40e47b1`, `build_number` = `11431`.
- Models: `Qwen3-0.6B-Q8_0.gguf` (Q8_0) and `Qwen3-4B-Q4_K_M.gguf` (Q4_K_M).
  Both are qwen3 with `attention.key_length = attention.value_length = 128`, i.e. head size 128,
  so both hit the head-128 branch of the block. `-ngl 99` (`n_gpu_layers` = 99 in every CSV row),
  KV cache f16/f16, `-fa 1`, `-b 2048`, `-p 512 -n 128`, `-d 0,2048,6144`, `-r 2`
  (llama-bench's own warmup left on).
- Card 1 only: `GGML_METAL_DEVICE_INDEX=1` with `-dev MTL0` (the `devices` column is `MTL0` in
  every row), `TOSH_FA_AMD=1` in the environment. The Metal backend probes the card itself and
  sets `TOSH_METAL_SIMD_WIDTH=64` (`ggml-metal-device.m`, `probed SIMD-group width = 64`), so the
  64-lane branch of the block is live in both arms of the A/B.
- Ubatch size: 128 and 512, four arms in total (2 models x 2 ubatch sizes).
- Two processes per setting, **alternating** new default / `TOSH_FA_PF_W64=1` / new default /
  `TOSH_FA_PF_W64=1` inside each (model, ubatch) group. 16 llama-bench processes in total,
  all in the foreground, one at a time, each wrapped in `perl -e 'alarm 2400; exec @ARGV'`.
  No GPU program ran during the build; no two GPU programs ran at once.
- llama-bench sets `n_ctx = n_prompt + n_gen + n_depth` (6784 at d6144).
- Wall clock: build 04:51-04:56, text runs 04:58-05:03, measurement 05:04-05:50.
- Verdict rule: "higher" only when **both** processes of one side lie above **both** processes
  of the other side; otherwise "not resolved".

### Commands

```
GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 perl -e 'alarm 2400; exec @ARGV' \
  build-fa/bin/llama-bench -m <model> -dev MTL0 -ngl 99 -fa 1 -ub <128|512> -b 2048 \
  -p 512 -n 128 -d 0,2048,6144 -r 2 -o csv

# new default: as above, TOSH_FA_PF_W64 unset
# old rule:     as above, TOSH_FA_PF_W64=1
```

Driver script: `run-bench.sh` (runs the 4 alternating processes of one group, then
`ls -t /Library/Logs/DiagnosticReports/ | head -3` after each process).

Raw data: `bench-<model>-ub<ub>-<new|old>-p<1|2>.csv` (16 files, 6 rows each) and the matching
`.err` files (no errors or warnings, only the normal Metal library compile messages).
Table builder: `summarize.py`.

## Table 1 - Qwen3-0.6B Q8_0, ubatch 128 (card 1, -b 2048, tok/s as printed)

| test | depth | new p1 (mean +- sd) | new p2 | old p1 | old p2 | verdict |
|---|---|---|---|---|---|---|
| pp512 | 0 | 498.454587 +- 1.144199 | 497.413986 +- 2.785039 | 447.308055 +- 0.546592 | 447.372935 +- 0.037441 | **new higher** |
| pp512 | 2048 | 320.252657 +- 0.528425 | 316.915927 +- 1.839588 | 178.718729 +- 0.094012 | 178.713993 +- 0.019941 | **new higher** |
| pp512 | 6144 | 183.621992 +- 0.077852 | 184.582890 +- 0.473811 | 81.066739 +- 0.000414 | 81.094016 +- 0.005966 | **new higher** |
| tg128 | 0 | 59.041368 +- 0.161175 | 59.116250 +- 0.008896 | 59.129777 +- 0.068357 | 58.822348 +- 0.147547 | not resolved |
| tg128 | 2048 | 45.463765 +- 0.073875 | 45.361594 +- 0.144239 | 45.452992 +- 0.011417 | 45.333572 +- 0.028251 | not resolved |
| tg128 | 6144 | 38.652443 +- 1.220454 | 39.233603 +- 0.352957 | 39.195353 +- 0.319334 | 39.234202 +- 0.394575 | not resolved |

## Table 2 - Qwen3-0.6B Q8_0, ubatch 512 (card 1, -b 2048, tok/s as printed)

| test | depth | new p1 (mean +- sd) | new p2 | old p1 | old p2 | verdict |
|---|---|---|---|---|---|---|
| pp512 | 0 | 615.850194 +- 0.155758 | 614.739404 +- 2.053078 | 546.560679 +- 1.790367 | 546.673041 +- 2.488146 | **new higher** |
| pp512 | 2048 | 404.860995 +- 1.759055 | 405.773356 +- 1.030517 | 201.659052 +- 0.033759 | 201.664463 +- 0.091638 | **new higher** |
| pp512 | 6144 | 236.089675 +- 1.710470 | 234.906265 +- 2.140180 | 85.461615 +- 0.497154 | 85.470444 +- 0.552712 | **new higher** |
| tg128 | 0 | 59.000776 +- 0.084764 | 59.046523 +- 0.082409 | 58.897020 +- 0.105785 | 58.967453 +- 0.065446 | **new higher** |
| tg128 | 2048 | 45.313865 +- 0.056092 | 45.360092 +- 0.063599 | 45.324121 +- 0.015659 | 45.354840 +- 0.042958 | not resolved |
| tg128 | 6144 | 39.267773 +- 0.408108 | 39.321621 +- 0.378366 | 39.159065 +- 0.477893 | 39.213706 +- 0.392709 | **new higher** |

## Table 3 - Qwen3-4B Q4_K_M, ubatch 128 (card 1, -b 2048, tok/s as printed)

| test | depth | new p1 (mean +- sd) | new p2 | old p1 | old p2 | verdict |
|---|---|---|---|---|---|---|
| pp512 | 0 | 92.912561 +- 0.045823 | 93.073515 +- 0.028397 | 87.947195 +- 0.014598 | 88.044625 +- 0.127531 | **new higher** |
| pp512 | 2048 | 76.460108 +- 0.006161 | 76.453456 +- 0.029343 | 51.953026 +- 0.028530 | 51.945014 +- 0.001036 | **new higher** |
| pp512 | 6144 | 56.133251 +- 0.009261 | 56.100559 +- 0.014777 | 27.598257 +- 0.000753 | 27.601909 +- 0.007446 | **new higher** |
| tg128 | 0 | 16.723221 +- 0.005768 | 16.718968 +- 0.009701 | 16.720343 +- 0.004145 | 16.715745 +- 0.001774 | not resolved |
| tg128 | 2048 | 14.850131 +- 0.006858 | 14.852337 +- 0.000787 | 14.842003 +- 0.016758 | 14.843001 +- 0.002643 | **new higher** |
| tg128 | 6144 | 12.135547 +- 0.001366 | 12.128903 +- 0.009004 | 12.134236 +- 0.001074 | 12.136224 +- 0.001443 | not resolved |

## Table 4 - Qwen3-4B Q4_K_M, ubatch 512 (card 1, -b 2048, tok/s as printed)

| test | depth | new p1 (mean +- sd) | new p2 | old p1 | old p2 | verdict |
|---|---|---|---|---|---|---|
| pp512 | 0 | 86.660660 +- 0.119243 | 86.549499 +- 0.016201 | 82.898617 +- 0.030902 | 82.927874 +- 0.075618 | **new higher** |
| pp512 | 2048 | 75.472961 +- 0.019156 | 75.463590 +- 0.020455 | 50.359944 +- 0.033013 | 50.372016 +- 0.015351 | **new higher** |
| pp512 | 6144 | 56.083189 +- 0.007373 | 56.129664 +- 0.018591 | 27.091961 +- 0.003957 | 27.132520 +- 0.020533 | **new higher** |
| tg128 | 0 | 16.710647 +- 0.005560 | 16.720741 +- 0.007059 | 16.711056 +- 0.023318 | 16.722800 +- 0.004032 | not resolved |
| tg128 | 2048 | 14.848803 +- 0.000461 | 14.847262 +- 0.005205 | 14.846324 +- 0.002561 | 14.850228 +- 0.003975 | not resolved |
| tg128 | 6144 | 12.131303 +- 0.002905 | 12.134574 +- 0.001493 | 12.131853 +- 0.003725 | 12.134915 +- 0.000359 | not resolved |

### Verdict list

Qwen3-0.6B Q8_0, ub 128: pp512 d0 new higher, pp512 d2048 new higher, pp512 d6144 new higher,
tg128 d0/d2048/d6144 not resolved.
Qwen3-0.6B Q8_0, ub 512: pp512 d0/d2048/d6144 new higher, tg128 d0 new higher, tg128 d2048 not
resolved, tg128 d6144 new higher.
Qwen3-4B Q4_K_M, ub 128: pp512 d0/d2048/d6144 new higher, tg128 d0 not resolved, tg128 d2048 new
higher, tg128 d6144 not resolved.
Qwen3-4B Q4_K_M, ub 512: pp512 d0/d2048/d6144 new higher, tg128 d0/d2048/d6144 not resolved.

Reading: every prefill row of every group is "new higher" - the block on 64 lanes costs prefill
throughput and the change recovers it. Decode rows are mostly "not resolved", which is the
expected result: the block only touches prompt batches, decode still rides flash attention.
The three decode rows that came out "new higher" (0.6B ub512 d0 and d6144, 4B ub128 d2048) are
noise-level differences (0.02 % to 0.25 %), not a decode effect.

The 4B ub128 numbers reproduce the ticket's premise exactly: new 92.9 / 76.5 / 56.1 tok/s
pp512 at depth 0 / 2048 / 6144 against old 88.0 / 51.9 / 27.6, decode 16.72 / 14.85 / 12.13 in
both arms.

## Text check - 4B, card 1, prompt6k.txt, `-ngl 99 -c 8192 -ub 128 -b 2048 -fa on -st --temp 0 -n 64 -s 1`

```
cmp text-new.gen text-w64.gen   ->  exit 0, no output (files identical)
sha256 text-new.gen = f6e3490d0d24c724e9c70f23386ed6677638df020e24b648af23bfa8f5016b92
sha256 text-w64.gen = f6e3490d0d24c724e9c70f23386ed6677638df020e24b648af23bfa8f5016b92
```

Extraction: from the line `[Start thinking]` up to, not including, the line beginning `[ Prompt`.
Both files are 316 bytes. The generated text is byte-identical between the new default and
`TOSH_FA_PF_W64=1` (the sha256 also matches the ticket-19 reference file).

Timings printed by llama-cli (whole-session rates, not bench rows):
- new default: `[ Prompt: 69.8 t/s | Generation: 12.1 t/s ]`
- `TOSH_FA_PF_W64=1`: `[ Prompt: 43.2 t/s | Generation: 12.1 t/s ]`

## Instruction-set gate

```
otool -tv build-fa/bin/llama-bench | grep -cE 'vfmadd|vfmsub|vfnmadd|vpbroadcast|vinserti128|vextracti128|vpgather'
0
```

## DiagnosticReports - before and after

Before (start of work, 2026-11-12 04:47), `ls -t /Library/Logs/DiagnosticReports/ | head -3`:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

After (end of work, 2026-11-12 05:52), `ls -t /Library/Logs/DiagnosticReports/ | head -3`:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

Identical. The directory holds 43 entries, the newest is still `codesign_2026-11-11-211515` from
the day before this work started. The check ran before the first GPU program and after every
llama-bench and llama-cli process (18 GPU processes in total). No `*.panic`, `*watchdog*` or
`*.gpuRestart` file was created today; the `Kernel-2026-11-11-083524.panic` is pre-existing.

## Not run / out of scope

- `test-backend-ops` was built (as specified) but not executed; the gates did not ask for it.
- Card 0 was never used, no other model, no depth above 6144, no layer split.
- 32-lane behaviour is unchanged by the diff and was not re-measured (this card is 64-lane).
- `TOSH_FA_PF_DISABLE` was not re-measured separately; it keeps its old meaning in the graph
  gate and still disables the Metal-side PF kernel in `ggml-metal-ops.cpp`.
- The change is uncommitted, as instructed. Nothing was committed, stashed, reset, checked out
  or cleaned. 127.0.0.1:8080, /Applications and all defaults domains untouched.
- `TOSH_FA_AMD=1` is in the environment as specified, but no source file reads that name
  (`grep -rn "TOSH_FA_AMD\b"` finds nothing); it has no effect on the numbers.
