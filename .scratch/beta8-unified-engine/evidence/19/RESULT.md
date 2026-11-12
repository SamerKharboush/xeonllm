# Ticket 19 — flash attention on/off, prefill and decode at several depths (card 1)

**Status: complete. All steps ran; nothing was skipped.**

## Method

Engine: `vendor/llama.cpp` at upstream pin `d81235049` ("bump version to 0.6.0") plus the local
92-patch series (`patches/llama/*.patch`, numbered 0001–0082, applied in numeric order).
`build-static/bin/llama-bench` sha256 `1a8385e315ae03024b47694a3b011f7f3f57fd5bf900cea47673fabad764c263`
(prefix `1a8385e315ae0302`); `build-static/bin/llama-cli` sha256
`f96866f469294a0c612768acb6e3c165fe0160b4b05953d1be796ed56aa43c36` (prefix `f96866f469294a0c`).
CSV rows report `build_commit` = `d81235049`, `build_number` = `11429`.
`llama-bench --help | grep -c -- "-d, --n-depth"` = **1** (the `-d/--n-depth` option exists).

Models: `Qwen3-0.6B-Q8_0.gguf` (Q8_0) and `Qwen3-4B-Q4_K_M.gguf` (Q4_K_M), `-ngl 99`
(`n_gpu_layers` = 99 in every CSV row), KV cache `f16`/`f16`, `-ub 128 -b 2048`, `-p 512 -n 128`,
`-d 0,2048,6144`, `-r 2` (llama-bench's own warmup left on, `--no-warmup` not passed).
Card 1 only: `GGML_METAL_DEVICE_INDEX=1` with `-dev MTL0` (accepted; `devices` column = `MTL0`,
no fallback needed), `TOSH_FA_AMD=1` in the environment.
Each process wrapped in `perl -e 'alarm 2400; exec @ARGV'`, run one at a time in the foreground,
never during a build (nothing was built).
Two processes per FA setting per model, **alternating** FA on/off/on/off in the order
rep1-fa1, rep1-fa0, rep2-fa1, rep2-fa0 (0.6B first, then 4B). No other model, no card 0, no
depth above 6144, no split over two cards.
llama-bench sets `n_ctx = n_prompt + n_gen + n_depth` (6784 at d6144).
Wall clock 2026-11-12 04:07–04:37 CET. A CPU-only `llama-server` (`Qwen3-14B-Q4_K_M`, `-ngl 0`,
127.0.0.1:8080) was already running and was left untouched; it was present for every process below.

### Commands

```
GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 perl -e 'alarm 2400; exec @ARGV' $B/llama-bench \
  -m <model> -dev MTL0 -ngl 99 -fa <1|0> -ub 128 -b 2048 -p 512 -n 128 \
  -d 0,2048,6144 -r 2 -o csv 2>>bench.err >>bench-<model>.csv

GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 perl -e 'alarm 2400; exec @ARGV' $B/llama-cli \
  -m /Users/sam/models/Qwen3-4B-Q4_K_M.gguf -dev MTL0 -ngl 99 -c 8192 -ub 128 -b 2048 \
  -fa <on|off> -st --temp 0 -n 64 -f .../evidence/18/prompt6k.txt -s 1 >text-fa<on|off>.out 2>/dev/null
```

Raw data: `bench-qwen3-0.6b-q8_0.csv` (4 processes × 6 rows + 4 header lines),
`bench-qwen3-4b-q4_k_m.csv` (4 processes × 6 rows + 4 header lines), `bench.err` (no errors or
warnings), `text-faon.out`, `text-faoff.out`, `text-faon.gen`, `text-faoff.gen`.

## Table 1 — Qwen3-0.6B Q8_0 (card 1, -ub 128 -b 2048, tok/s as printed)

| test | FA on, process 1 | FA on, process 2 | FA off, process 1 | FA off, process 2 | verdict |
|---|---|---|---|---|---|
| pp512 @ d0 | 447.552636 ± 0.172260 | 447.638060 ± 0.082613 | 518.498294 ± 3.612598 | 518.571566 ± 3.182387 | **FA off higher** |
| tg128 @ d0 | 58.936065 ± 0.196789 | 58.746033 ± 0.257901 | 53.934638 ± 0.089785 | 53.953469 ± 0.053636 | **FA on higher** |
| pp512 @ d2048 | 178.706024 ± 0.065417 | 178.726327 ± 0.096150 | 371.223255 ± 1.283834 | 370.794586 ± 3.540294 | **FA off higher** |
| tg128 @ d2048 | 45.332732 ± 0.130687 | 45.335530 ± 0.071382 | 32.648831 ± 0.437614 | 32.824174 ± 0.005384 | **FA on higher** |
| pp512 @ d6144 | 81.071813 ± 0.000514 | 81.042567 ± 0.010371 | 240.144840 ± 0.218464 | 240.271306 ± 0.182997 | **FA off higher** |
| tg128 @ d6144 | 39.205599 ± 0.396660 | 39.210017 ± 0.401583 | 18.426500 ± 0.017944 | 18.303112 ± 0.003592 | **FA on higher** |

Verdict rule applied: "higher" only when **both** processes of one side lie above **both**
processes of the other side. All six rows are resolved.

## Table 2 — Qwen3-4B Q4_K_M (card 1, -ub 128 -b 2048, tok/s as printed)

| test | FA on, process 1 | FA on, process 2 | FA off, process 1 | FA off, process 2 | verdict |
|---|---|---|---|---|---|
| pp512 @ d0 | 87.999568 ± 0.043177 | 88.015833 ± 0.030557 | 93.546173 ± 0.051483 | 93.504034 ± 0.043756 | **FA off higher** |
| tg128 @ d0 | 16.718364 ± 0.002582 | 16.712045 ± 0.008941 | 15.717425 ± 0.006256 | 15.709754 ± 0.012420 | **FA on higher** |
| pp512 @ d2048 | 51.943772 ± 0.017646 | 51.941857 ± 0.003448 | 79.223726 ± 0.005737 | 79.204575 ± 0.056695 | **FA off higher** |
| tg128 @ d2048 | 14.843375 ± 0.002719 | 14.845680 ± 0.004120 | 10.815878 ± 0.005205 | 10.854431 ± 0.003269 | **FA on higher** |
| pp512 @ d6144 | 27.596266 ± 0.001247 | 27.602607 ± 0.005178 | 60.208800 ± 0.025074 | 60.159788 ± 0.081054 | **FA off higher** |
| tg128 @ d6144 | 12.128966 ± 0.003222 | 12.135337 ± 0.001204 | 6.545669 ± 0.001063 | 6.572705 ± 0.001312 | **FA on higher** |

Verdict rule applied as above. All six rows are resolved.

### Row-by-row verdict list

Qwen3-0.6B Q8_0
- pp512 @ d0 — FA off higher
- tg128 @ d0 — FA on higher
- pp512 @ d2048 — FA off higher
- tg128 @ d2048 — FA on higher
- pp512 @ d6144 — FA off higher
- tg128 @ d6144 — FA on higher

Qwen3-4B Q4_K_M
- pp512 @ d0 — FA off higher
- tg128 @ d0 — FA on higher
- pp512 @ d2048 — FA off higher
- tg128 @ d2048 — FA on higher
- pp512 @ d6144 — FA off higher
- tg128 @ d6144 — FA on higher

Reading of the tables (no modelled baseline, no percentages): with FA off the prefill rate is the
higher one at every depth for both models, and the gap widens with depth. With FA on the decode
rate is the higher one at every depth for both models, and the gap widens with depth. The two
effects are opposite, so "FA off" is not a free win: it trades decode throughput for prefill
throughput, and which one matters depends on how much of the session is prefill versus decode.

## Text check — 4B, card 1, prompt6k.txt, `-c 8192 -ub 128 -b 2048 -st --temp 0 -n 64 -s 1`

```
cmp text-faon.gen text-faoff.gen   ->  exit 0, no output (files identical)
sha256 text-faon.gen  = f6e3490d0d24c724e9c70f23386ed6677638df020e24b648af23bfa8f5016b92
sha256 text-faoff.gen = f6e3490d0d24c724e9c70f23386ed6677638df020e24b648af23bfa8f5016b92
```

Extraction: from the line `[Start thinking]` up to, not including, the line beginning `[ Prompt`.
Both files are 316 bytes. The generated text is byte-identical between FA on and FA off.

Timings printed by llama-cli (whole-session rates, not the bench rows):
- FA on: `[ Prompt: 43.2 t/s | Generation: 12.1 t/s ]`
- FA off: `[ Prompt: 72.2 t/s | Generation: 6.5 t/s ]`

The only other differences between the two full stdout files are the model-loading spinner and that
timing line.

## DiagnosticReports — before and after

Before (start of work, 2026-11-12 04:04), `ls -t /Library/Logs/DiagnosticReports/ | head -3`:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

After (end of work, 2026-11-12 04:37), `ls -t /Library/Logs/DiagnosticReports/ | head -3`:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

Identical. The directory holds 43 entries; the newest is still `codesign_2026-11-11-211515` from
the day before the work started. No `*.panic`, `*watchdog*` or `*.gpuRestart` file was created on
2026-11-12 — checked after every llama-bench process and after both llama-cli runs. The
`Kernel-2026-11-11-083524.panic` is pre-existing (2026-11-11 08:35), not from this work.

## Not run / out of scope

- Card 0, and the "both cards" part of the ticket-19 issue text: only card 1 was measured, as the
  safety rules for this ticket require.
- Models other than the two named (no 8B, no 14B, no layer split).
- Quantised KV (`-ctk/-ctv`): all rows used f16 KV, so nothing here says what FA on/off does with
  turbo-KV, where FA is required.
- N=2 processes per FA setting, as the steps specify; the issue text asks for N>=3.
- No build was run, no source/script/patch/spec was edited, nothing was committed, tagged, pushed,
  stashed, reset or checked out. 127.0.0.1:8080, /Applications and all defaults domains untouched.
- The prompt file `evidence/18/prompt6k.txt` was used as-is (30.1 KB); the token count printed by
  llama-cli on stderr was discarded by the `2>/dev/null` in the specified command, so the exact
  prompt length in tokens was not recorded.
