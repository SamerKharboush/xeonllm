# XeonLLM 0.87.31-beta.8 vs ToshLLM 0.87.33 — engine-level llama-bench comparison

Measurement only. No source edited, nothing built. No app launched. Only the bundled
`llama-bench` binaries under `Contents/Resources/bin` were executed, strictly one process at
a time, foreground, each under `perl -e 'alarm 1200; exec @ARGV'`.

Wall clock: started 2026-11-13 18:23:52 CET, driver finished 20:35:49 CET (≈2 h 12 min,
inside the 3 h budget).

## Method (applies to every table below)

- Engines: ToshLLM `llama-bench` sha256 `5977c1a9e6379dcd…` (bundle 0.87.33) vs XeonLLM
  `llama-bench` sha256 `93db3d0cd285ec50…` (bundle 0.87.31-beta.8). Both report
  `version: 0.6.0-dev (build 11429, commit d81235049)`.
- Card 1 only: `GGML_METAL_DEVICE_INDEX=1` → MTL0 `AMD Radeon HD - FirePro D700`, 6144 MiB,
  MTLGPUFamilyCommon3. Card 0 (display) untouched.
- Flags: `-ngl 99 -fa 1 -ub 128 -r 5 -o csv`, plus `-p 512,2048 -n 128` (cell A) or
  `-p 0 -n 128 -d 2048` (cell D). `TOSH_FA_AMD=1` on every process.
- N = 3 processes per side, alternating T, X, T, X, T, X (labels t1 x1 t2 x2 t3 x3), one at a
  time, nothing else heavy running.
- Values are `avg_ts ± stddev_ts` copied verbatim from each process's own CSV. The warm-up run
  that llama-bench does internally is discarded by llama-bench itself; every process contributes
  exactly one value per row.
- "both above/below" is strict: "X above" only if all three X values are above all three T
  values; "T above" for the reverse; otherwise "overlap". No percentages, no ratios.

Engine feature lines from the first 25 stderr lines of the first process of each engine (identical
for every model on each engine, except LFM3 on T which stops before benchmarking):

```
                        ToshLLM (fp e12176b637c7)          XeonLLM (fp f43dd4109052)
probed SIMD-group width 64                              64
wave64 mode             GPU prefill matmul, CPU decode/…  GPU prefill matmul, CPU decode/…
aligned mat-vec reads   ON by amdgpu_gfx600               ON by amdgpu_gfx600
wave64 decode           ON                                ON
tensor API              disabled (pre-M5 / pre-A19)       disabled (pre-M5 / pre-A19)
residency sets          true                              true
shared buffers          false                             false
```

One engine-visible difference beyond the fingerprint: ToshLLM's Metal pipeline compilation fails
repeatedly for the flash-attention kernels (`failed to create pipeline state: base =
'kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16[_w64_lg16]'`, `CompilerError Code=2 … GPGPU,
exceed the local data storage limit`), 3362 such lines for the 0.6B A cells, 4322 for the 4B/8B A
cells, 450–578 for the D cells, in every T process. XeonLLM's stderr has zero such lines in all 30
processes. This is recorded as observed stderr, not as an explanation of any number.

## Qwen3-0.6B-Q8_0

| metric | t1 | t2 | t3 | x1 | x2 | x3 | both above/below |
|---|---|---|---|---|---|---|---|
| pp512 | 447.532164 ± 0.101820 | 447.765968 ± 0.272286 | 447.954000 ± 0.268047 | 497.339837 ± 2.116739 | 496.337010 ± 2.148573 | 497.173879 ± 3.105215 | X above |
| pp2048 | 285.804499 ± 0.040469 | 285.855506 ± 0.036435 | 285.826940 ± 0.085110 | 409.565644 ± 1.736581 | 409.738998 ± 1.182047 | 408.773328 ± 1.007223 | X above |
| tg128 | 58.960051 ± 0.201938 | 59.080484 ± 0.040009 | 59.132594 ± 0.083968 | 58.934414 ± 0.114544 | 59.045275 ± 0.067571 | 59.027421 ± 0.056459 | overlap |
| tg128 @ d2048 | 45.475811 ± 0.046394 | 45.477610 ± 0.043187 | 45.420772 ± 0.050504 | 45.448182 ± 0.034602 | 45.428020 ± 0.040835 | 45.417029 ± 0.076409 | overlap |

Method: ToshLLM `5977c1a9e6379dcd` / 0.87.33, XeonLLM `93db3d0cd285ec50` / 0.87.31-beta.8; card 1
(D700); Qwen3-0.6B-Q8_0; `-fa 1 -ub 128 -r 5`; A: `-p 512,2048 -n 128`, D: `-p 0 -n 128 -d 2048`;
N=3 per side alternating; warmup run discarded; `TOSH_FA_AMD=1`.

## Qwen3-4B-Q4_K_M

| metric | t1 | t2 | t3 | x1 | x2 | x3 | both above/below |
|---|---|---|---|---|---|---|---|
| pp512 | 88.033865 ± 0.067661 | 88.025318 ± 0.053042 | 88.002298 ± 0.049538 | 93.047103 ± 0.071763 | 93.081894 ± 0.066819 | 93.037640 ± 0.034221 | X above |
| pp2048 | 69.549555 ± 0.001860 | 69.549304 ± 0.024747 | 69.542923 ± 0.016157 | 85.957956 ± 0.034174 | 85.969785 ± 0.026243 | 85.970976 ± 0.035284 | X above |
| tg128 | 14.144467 ± 0.002557 | 14.141165 ± 0.005926 | 14.139156 ± 0.004069 | 16.713046 ± 0.006329 | 16.712537 ± 0.006284 | 16.710552 ± 0.009877 | X above |
| tg128 @ d2048 | 12.787219 ± 0.002546 | 12.783959 ± 0.002268 | 12.784818 ± 0.002999 | 14.844522 ± 0.004555 | 14.840510 ± 0.005904 | 14.844692 ± 0.004776 | X above |

Method: as above; model Qwen3-4B-Q4_K_M; A `-p 512,2048 -n 128`, D `-p 0 -n 128 -d 2048`.

## Qwen3-4B-Q6_K

| metric | t1 | t2 | t3 | x1 | x2 | x3 | both above/below |
|---|---|---|---|---|---|---|---|
| pp512 | 83.318895 ± 0.034331 | 83.295189 ± 0.024683 | 83.323190 ± 0.041383 | 87.680211 ± 0.044605 | 87.711078 ± 0.032313 | 87.634645 ± 0.063691 | X above |
| pp2048 | 66.785258 ± 0.021240 | 66.778682 ± 0.011236 | 66.766935 ± 0.018918 | 81.434872 ± 0.030719 | 81.456567 ± 0.026967 | 81.428567 ± 0.022789 | X above |
| tg128 | 12.102414 ± 0.004163 | 12.105417 ± 0.003472 | 12.101897 ± 0.004737 | 13.914786 ± 0.004824 | 13.914051 ± 0.005514 | 13.916984 ± 0.001286 | X above |
| tg128 @ d2048 | 11.096253 ± 0.003947 | 11.096022 ± 0.001819 | 11.095586 ± 0.002766 | 12.601504 ± 0.003343 | 12.600451 ± 0.003290 | 12.601712 ± 0.001086 | X above |

Method: as above; model Qwen3-4B-Q6_K; A `-p 512,2048 -n 128`, D `-p 0 -n 128 -d 2048`.

## Qwen3-8B-Q4_K_M

| metric | t1 | t2 | t3 | x1 | x2 | x3 | both above/below |
|---|---|---|---|---|---|---|---|
| pp512 | 53.350121 ± 0.018436 | 53.351767 ± 0.017533 | 53.353117 ± 0.018952 | 55.132168 ± 0.008918 | 55.135079 ± 0.026031 | 55.142668 ± 0.023245 | X above |
| pp2048 | 45.555063 ± 0.009146 | 45.557214 ± 0.012186 | 45.559268 ± 0.009469 | 52.532040 ± 0.008421 | 52.540838 ± 0.005924 | 52.544300 ± 0.005373 | X above |
| tg128 | 8.271712 ± 0.001926 | 8.270775 ± 0.002069 | 8.273277 ± 0.001649 | 10.247127 ± 0.002795 | 10.248488 ± 0.000781 | 10.246875 ± 0.001697 | X above |
| tg128 @ d2048 | 7.792937 ± 0.000771 | 7.791727 ± 0.001816 | 7.792485 ± 0.000529 | 9.507772 ± 0.001585 | 9.506726 ± 0.001445 | 9.505278 ± 0.004053 | X above |

Method: as above; model Qwen3-8B-Q4_K_M; A `-p 512,2048 -n 128`, D `-p 0 -n 128 -d 2048`.

## LFM3-1.7B-F16

| metric | t1 | t2 | t3 | x1 | x2 | x3 | both above/below |
|---|---|---|---|---|---|---|---|
| pp512 | not run | not run | not run | 254.229394 ± 0.364127 | 254.439915 ± 0.341094 | 254.370785 ± 0.443988 | n/a |
| pp2048 | not run | not run | not run | 250.116776 ± 0.063058 | 250.180613 ± 0.088762 | 249.996786 ± 0.097129 | n/a |
| tg128 | not run | not run | not run | 23.072202 ± 0.025669 | 23.067534 ± 0.018975 | 23.057259 ± 0.003843 | n/a |
| tg128 @ d2048 | not run | not run | not run | 22.462575 ± 0.017571 | 22.491377 ± 0.010181 | 22.483827 ± 0.004562 | n/a |

Method: as above; model LFM3-1.7B-F16; ToshLLM side refused the model.

Cells not run, and why:

- **LFM3-1.7B-F16, ToshLLM, all 6 cells (A t1/t2/t3, D t1/t2/t3)** — not loadable on ToshLLM
  0.87.33. Every T process exited rc=1 with a header-only CSV (0 data rows). Quoted stderr,
  identical in all six:
  ```
  llama_model_load: error loading model: unknown model architecture: 'lfm3'
  llama_model_load_from_file_impl: failed to load model
  llama_bench: error: failed to load model '/Users/sam/models/LFM3-1.7B-F16.gguf'
  ```
  The error line appears after the engine's device/feature block, i.e. the engine itself starts
  fine and rejects the architecture. No XeonLLM cell was skipped; all 12 XeonLLM processes across
  the 5 models ran and produced data.

All other cells ran: 4 models × 2 cells × 6 processes = 48 processes, plus 6 XeonLLM-only LFM3
processes = 54 processes total, all rc=0.

## Safety checks

- Every process wrapped in `perl -e 'alarm 1200; exec @ARGV'`; strictly foreground and sequential;
  no builds, no other heavy work.
- DiagnosticReports compared after the matrix: `comm -13 diag-first.txt diag-now.txt` produced
  **no output** — no new `panic`, `watchdog` or `gpuRestart` entries (the pre-existing Nov 6–11
  entries in the baseline are untouched, and the OS pruning of stale entries is not a crash).
- `~/Library/Application Support/ToshLLM` and `~/Library/Application Support/XeonLLM` listings
  before vs after are byte-identical (`diff` empty). No defaults domains touched, no writes into
  either Application Support tree, 127.0.0.1:8080 never contacted, neither app launched.