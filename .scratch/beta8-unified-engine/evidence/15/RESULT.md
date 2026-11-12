# Beta 8 — Ticket 15 — Quantised KV cache on AMD card 1 (Metal flash attention)

## Method

Binaries (sha256, first 16 hex): `llama-bench` `ca187698a5d10fb5`, `llama-cli` `c6fb501a09cb52f1`,
`test-backend-ops` `4eafec72b023bedd` — all from
`/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin` (build tag `b11431-6a40e47b1`).
Engine: series 0001-0082 + metal/0083 on pin `d81235049` (worktree HEAD `6a40e47b1`,
parent `731b358fd`, merge-base with `d81235049` = `d81235049`), with the uncommitted local
`src/llama-graph.cpp` diff (8+/3−) that keeps the wave64 FA prefill block off unless
`TOSH_FA_PF_W64=1`.

Models: `Qwen3-4B-Q4_K_M.gguf` (Q4_K - Medium, 4B, 36 layers) and `Qwen3-0.6B-Q8_0.gguf`
(Q8_0) — the 0.6B is used only for the llama-bench tables.
Bench flags: `-ngl 99`, `-fa 1`, `-ub 128`, `-b 2048`, `-p 512 -n 128 -d 0,2048,6144`, `-r 2`,
`-o csv`, `-dev MTL0`, with `GGML_METAL_DEVICE_INDEX=1` (physical GPU 1 = logical MTL0,
AMD Radeon HD FirePro D700, wave64 / SIMD width 64). llama-bench has no `-c` flag: it sets
`cparams.n_ctx = n_prompt + n_gen + n_depth` per row, so bench context is 512 / 2560 / 6656
(pp512 at d0 / d2048 / d6144) and 128 / 2176 / 6272 (tg128 at d0 / d2048 / d6144) — max 6656,
i.e. ≤ 8192 as required. The llama-cli runs used `-c 8192 -ub 128 -b 2048`.

Two processes per KV setting, rotating f16 → q8q8 → q8q4 (pass 1 = f16, q8q8, q8q4; pass 2 =
f16, q8q8, q8q4; 4B at 06:24–06:44, 0.6B at 06:45–06:51). llama-bench's own warmup was left
enabled (default; no `--no-warmup`), so each test does a warmup prompt run and a warmup
generation run before the measured repetitions. Every GPU program ran in the foreground, one at
a time, wrapped in `perl -e 'alarm 1800; exec @ARGV'`. Nothing was rebuilt; no source, script,
patch or spec was edited.

Card 1 only: `GGML_METAL_DEVICE_INDEX=1` + `-dev MTL0` (test-backend-ops: `-b MTL0`).

## test-backend-ops — FLASH_ATTN_EXT on MTL0 (card 1)

Command: `GGML_METAL_DEVICE_INDEX=1 perl -e 'alarm 1800; exec @ARGV' test-backend-ops -b MTL0 -o FLASH_ATTN_EXT`
→ `tbo-fa.txt` (full log), `tbo-fa-cases.stripped.txt` (5517 parsed case lines),
`tbo-fa-q84-hsk128.txt` (hsk=128 quantised subset), `tbo-fa-q84-hsk128-notok.txt`.

```
  1993/1993 tests passed
Running FA vec slice tests (env LLAMA_TEST_FA_VEC_DISABLE=1 to skip)
  fa_vec (Q,NE) slice: 240 cases run, 0 failed
  Backend MTL0: OK
3/3 backends passed
OK
```

5517 FA case lines: **1993 OK, 3524 not supported, 0 FAIL** (no FAIL string anywhere in the
full log). Head size 128 with `type_K` or `type_V` in {q8_0, q4_0}: 54 cases → 52 OK,
2 not supported, 0 FAIL. The 2 not-supported are `type_K=q1_0,type_V=q4_0` and
`type_K=q2_0,type_V=q4_0` (hsk=128, hsv=64) — not the q8_0/q4_0 pairs. Strictly both-quantised
hsk=128 (hsv=128): 23 cases, **23 OK, 0 FAIL** — {q8_0,q8_0}: 10, {q4_0,q4_0}: 7,
{q8_0,q4_0}: 3, {q4_0,q8_0}: 3.

## KV table (llama-cli, 4B Q4_K_M, `-c 8192 -ub 128 -b 2048`, `-fa on`, prompt6k.txt, `--temp 0 -n 200 -s 1`)

| setting | KV cache size | FA on/off | text cmp vs f16 | prompt/gen rate line |
|---|---|---|---|---|
| f16 (`-ctk f16 -ctv f16`) | 1152.00 MiB (K 576.00 / V 576.00) | on | baseline (identical to itself) | `[ Prompt: 69.8 t/s \| Generation: 12.0 t/s ]` |
| q8q8 (`-ctk q8_0 -ctv q8_0`) | 612.00 MiB (K 306.00 / V 306.00) | on | differs: first differing char at 0-based index 699 (1-based char 700) | `[ Prompt: 69.1 t/s \| Generation: 10.4 t/s ]` |
| q8q4 (`-ctk q8_0 -ctv q4_0`) | 468.00 MiB (K 306.00 / V 162.00) | on | differs: first differing char at 0-based index 596 (1-based char 597) | `[ Prompt: 69.3 t/s \| Generation: 10.3 t/s ]` |

First 300 chars of the generated text are identical for all three settings; divergence is later
in the reasoning text, consistent with quantisation-induced drift (same prompt, temp 0, seed 1).
q8q8 vs q8q4 also differ from each other, first differing char at 0-based index 596.
Each setting was run twice (plain and `LLAMA_ARG_LOG_VERBOSITY=4`); the generated text was
byte-identical between the two runs for every setting (the only `.out` difference is the q8q8
prompt-rate line, 69.1 vs 69.3 t/s).

KV memory saved at `-c 8192`, 4B, 36 layers, 1 sequence: f16 1152.00 MiB → q8q8 612.00 MiB
(540.00 MiB less) → q8q4 468.00 MiB (684.00 MiB less than f16, 144.00 MiB less than q8q8).

FA stayed enabled for all three KV types — `llama_context: flash_attn = enabled` in every run,
and the Metal driver fallback message names the FA kernel actually dispatched:
- f16 → `kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_lds32`
- q8q8 → `kernel_flash_attn_ext_vec_amd_dk128_kq8_0_vq8_0_w64_lds32`
- q8q4 → `kernel_flash_attn_ext_vec_amd_dk128_kq8_0_vq4_0_w64_lds32`

KV cache size lines (verbosity 4, `text-*.v.err` and `kvsize-*.err`):

```
llama_kv_cache: MTL0_Private KV buffer size =  1152.00 MiB
llama_kv_cache: size = 1152.00 MiB (  8192 cells,  36 layers,  1/1 seqs), K (f16):  576.00 MiB, V (f16):  576.00 MiB
llama_kv_cache: MTL0_Private KV buffer size =   612.00 MiB
llama_kv_cache: size =  612.00 MiB (  8192 cells,  36 layers,  1/1 seqs), K (q8_0):  306.00 MiB, V (q8_0):  306.00 MiB
llama_kv_cache: MTL0_Private KV buffer size =   468.00 MiB
llama_kv_cache: size =  468.00 MiB (  8192 cells,  36 layers,  1/1 seqs), K (q8_0):  306.00 MiB, V (q4_0):  162.00 MiB
```

## Speed tables (llama-bench, card 1, `-fa 1 -ub 128 -b 2048 -p 512 -n 128 -d 0,2048,6144 -r 2`, t/s)

Verdict rule: "<setting> higher" only when **both** processes of that setting lie above **both**
processes of each other setting; otherwise "not resolved".

### Qwen3-4B-Q4_K_M.gguf (4B, Q4_K - Medium)

| row | f16 p1 | f16 p2 | q8q8 p1 | q8q8 p2 | q8q4 p1 | q8q4 p2 | verdict |
|---|---|---|---|---|---|---|---|
| pp512 d0 | 92.98 ± 0.06 | 92.93 ± 0.03 | 91.69 ± 0.04 | 91.75 ± 0.06 | 91.71 ± 0.02 | 91.61 ± 0.02 | f16 higher |
| pp512 d2048 | 76.47 ± 0.03 | 76.49 ± 0.03 | 74.60 ± 0.02 | 74.63 ± 0.02 | 75.12 ± 0.04 | 75.10 ± 0.04 | f16 higher |
| pp512 d6144 | 56.12 ± 0.02 | 56.11 ± 0.01 | 54.80 ± 0.05 | 54.81 ± 0.05 | 54.77 ± 0.02 | 54.79 ± 0.00 | f16 higher |
| tg128 d0 | 16.71 ± 0.01 | 16.71 ± 0.01 | 15.61 ± 0.01 | 15.61 ± 0.00 | 15.65 ± 0.01 | 15.65 ± 0.00 | f16 higher |
| tg128 d2048 | 14.84 ± 0.02 | 14.85 ± 0.00 | 13.50 ± 0.00 | 13.49 ± 0.01 | 13.47 ± 0.01 | 13.47 ± 0.00 | f16 higher |
| tg128 d6144 | 12.13 ± 0.00 | 12.13 ± 0.00 | 10.52 ± 0.00 | 10.52 ± 0.00 | 10.42 ± 0.00 | 10.42 ± 0.00 | f16 higher |

### Qwen3-0.6B-Q8_0.gguf (0.6B, Q8_0)

| row | f16 p1 | f16 p2 | q8q8 p1 | q8q8 p2 | q8q4 p1 | q8q4 p2 | verdict |
|---|---|---|---|---|---|---|---|
| pp512 d0 | 496.01 ± 2.17 | 496.80 ± 2.79 | 479.03 ± 0.18 | 479.57 ± 0.30 | 489.89 ± 2.31 | 481.94 ± 1.75 | f16 higher |
| pp512 d2048 | 320.01 ± 0.93 | 317.70 ± 2.80 | 305.32 ± 0.41 | 309.69 ± 3.94 | 309.46 ± 0.90 | 309.39 ± 1.24 | f16 higher |
| pp512 d6144 | 184.02 ± 1.22 | 184.03 ± 0.64 | 180.29 ± 0.78 | 180.95 ± 0.49 | 179.85 ± 1.40 | 178.95 ± 0.64 | f16 higher |
| tg128 d0 | 59.08 ± 0.10 | 59.16 ± 0.05 | 46.73 ± 0.03 | 46.58 ± 0.05 | 46.95 ± 0.13 | 47.00 ± 0.19 | f16 higher |
| tg128 d2048 | 45.37 ± 0.02 | 45.34 ± 0.15 | 34.38 ± 0.14 | 34.37 ± 0.07 | 35.19 ± 0.03 | 35.20 ± 0.01 | f16 higher |
| tg128 d6144 | 39.22 ± 0.37 | 39.28 ± 0.39 | 31.06 ± 0.72 | 31.35 ± 0.20 | 28.50 ± 0.65 | 28.81 ± 0.25 | f16 higher |

Values are `avg_ts ± stddev_ts` as printed by llama-bench (mean and sd over that process's own
`-r 2` repetitions). Every row's `flash_attn` CSV column reads `1`, `n_batch` 2048, `n_ubatch`
128, `n_gpu_layers` 99, `type_k`/`type_v` matching the row's setting.

## cmp lines (generated text, llama-cli 4B, prompt6k.txt, `--temp 0 -n 200 -s 1`)

```
$ cmp text-f16.gen text-q8q8.gen
text-f16.gen text-q8q8.gen differ: char 700, line 5
$ cmp text-f16.gen text-q8q4.gen
text-f16.gen text-q8q4.gen differ: char 597, line 5
$ cmp text-q8q8.gen text-q8q4.gen
text-q8q8.gen text-q8q4.gen differ: char 597, line 5
```

The plain and the verbosity-4 run of each setting produced byte-identical `.gen` for f16,
q8q8 and q8q4. The first 300 characters are identical across all three settings.

## DiagnosticReports — before and after

Before (checked 06:02:59 CET, before the first GPU program) and after (07:07:58 CET, after the
last one) — identical, three newest:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

The `Kernel-2026-11-11-083524.panic` is pre-existing (dated the day before the session). No new
`*.panic`, `*watchdog*` or `*.gpuRestart` report was produced by any run.

## Files

- `tbo-fa.txt`, `tbo-fa-cases.stripped.txt`, `tbo-fa-q84-hsk128.txt`, `tbo-fa-q84-hsk128-notok.txt` — test-backend-ops FLASH_ATTN_EXT log and parsed case subsets
- `text-{f16,q8q8,q8q4}.out/.err/.gen` — llama-cli plain runs (generation extracted)
- `text-{f16,q8q8,q8q4}.v.out/.err/.v.gen` — llama-cli verbosity-4 runs (KV size lines, `flash_attn = enabled`)
- `kvsize-{f16,q8q8,q8q4}.out/.err` — short verbosity-4 runs used for the KV size lines
- `bench-{4b,06b}-{f16,q8q8,q8q4}-p{1,2}.csv/.err` — 12 llama-bench runs
- `flagcheck.csv/.err` — flag-acceptance pre-check

## Not run / caveats

- **FA off was not measured** for any KV type. The engine refuses quantised V when FA is off
  ("quantized V cache was requested, but this requires Flash Attention"), so a FA-off row exists
  only for f16, and the ticket's FA on/off column reports the state actually observed (on for all
  three).
- **KV cache size was measured only for the 4B model** at `-c 8192` (`text-*.v.err` /
  `kvsize-*.err`). llama-bench is non-verbose and prints no KV size line; the 0.6B bench rows
  carry no KV size figure.
- **The wave64 FA prefill block was not exercised**: `TOSH_FA_PF_W64` was never set, so the
  uncommitted `src/llama-graph.cpp` diff leaves the wave64 FA prefill block off and prefill runs
  the decomposed route while decode uses FA. This is read from the source diff, not measured here.
- **No perplexity / embedding equivalence check** for the quantised KV types; correctness evidence
  is the tbo case results plus the text comparison against f16.
- **No CPU-only or card-0 baseline** was run; all numbers are card 1 Metal.
- **No `TOSH_FA_PF_W64=1` run, no `q4_0/q4_0` KV pair, and no `-ctv f16` with quantised K** were
  run — out of scope of this ticket.
- **No percentage figures against modelled or projected values** are given anywhere; only
  measured MiB and measured t/s are reported.
