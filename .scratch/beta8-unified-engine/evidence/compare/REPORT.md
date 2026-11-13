# XeonLLM 0.87.31-beta.8 against the original ToshLLM 0.87.33 (2026-11-13)

Same Mac Pro 6,1 (Xeon E5-2697 v2, 64 GB, 2x FirePro D700, macOS 15.8), same model files, each app's
own bundled binaries run directly. Neither app was launched: ToshLLM.app has no test-profile option
and would write into the user's settings and data folder. Both engines report llama.cpp build 11429,
commit `d81235049`. Engines (sha256 prefix): ToshLLM llama-bench `5977c1a9e6379dcd`, llama-server
`f3e4ec060b77430c`; XeonLLM beta 8 llama-bench `93db3d0cd285ec50`, llama-server `63eb2a01af361672`.
Measured by Mocca, checked by the orchestrator against the saved CSV/JSON files. No new panic,
watchdog or gpuRestart report; ToshLLM's and XeonLLM's Application Support folders unchanged.

"beta 8 above" means every beta 8 process read above every ToshLLM process; "overlap" otherwise.

## 1. Engine level (engine/)

Method: each app's `llama-bench`, card 1 only (`GGML_METAL_DEVICE_INDEX=1`), `TOSH_FA_AMD=1`,
`-ngl 99 -fa 1 -ub 128 -r 5`, prompt `-p 512,2048`, decode `-n 128` at depth 0 and `-d 2048`; three
processes per side alternating ToshLLM / beta 8; llama-bench's warmup run discarded. Values: avg tok/s
per process. Decode at depth 2048, not 4096, and `-ub 128` for both: ToshLLM's engine has no
command-buffer time bound, and long GPU command buffers have panicked this Mac.

| model | cell | ToshLLM 0.87.33 | beta 8 | |
|---|---|---|---|---|
| Qwen3-0.6B Q8_0 | pp512 | 447.53 / 447.77 / 447.95 | 497.34 / 496.34 / 497.17 | beta 8 above |
| | pp2048 | 285.80 / 285.86 / 285.83 | 409.57 / 409.74 / 408.77 | beta 8 above |
| | tg128 | 58.96 / 59.08 / 59.13 | 58.93 / 59.05 / 59.03 | overlap |
| | tg128 @ d2048 | 45.48 / 45.48 / 45.42 | 45.45 / 45.43 / 45.42 | overlap |
| Qwen3-4B Q4_K_M | pp512 | 88.03 / 88.03 / 88.00 | 93.05 / 93.08 / 93.04 | beta 8 above |
| | pp2048 | 69.55 / 69.55 / 69.54 | 85.96 / 85.97 / 85.97 | beta 8 above |
| | tg128 | 14.14 / 14.14 / 14.14 | 16.71 / 16.71 / 16.71 | beta 8 above |
| | tg128 @ d2048 | 12.79 / 12.78 / 12.78 | 14.84 / 14.84 / 14.84 | beta 8 above |
| Qwen3-4B Q6_K | pp512 | 83.32 / 83.30 / 83.32 | 87.68 / 87.71 / 87.63 | beta 8 above |
| | pp2048 | 66.79 / 66.78 / 66.77 | 81.43 / 81.46 / 81.43 | beta 8 above |
| | tg128 | 12.10 / 12.11 / 12.10 | 13.91 / 13.91 / 13.92 | beta 8 above |
| | tg128 @ d2048 | 11.10 / 11.10 / 11.10 | 12.60 / 12.60 / 12.60 | beta 8 above |
| Qwen3-8B Q4_K_M | pp512 | 53.35 / 53.35 / 53.35 | 55.13 / 55.14 / 55.14 | beta 8 above |
| | pp2048 | 45.56 / 45.56 / 45.56 | 52.53 / 52.54 / 52.54 | beta 8 above |
| | tg128 | 8.27 / 8.27 / 8.27 | 10.25 / 10.25 / 10.25 | beta 8 above |
| | tg128 @ d2048 | 7.79 / 7.79 / 7.79 | 9.51 / 9.51 / 9.51 | beta 8 above |
| LFM3-1.7B F16 | all | does not load: "unknown model architecture: 'lfm3'" | pp512 254.23-254.44, pp2048 250.00-250.18, tg128 23.06-23.07, @ d2048 22.46-22.49 | |

## 2. Whole machine (machine/)

Method: each engine's `llama-server` with the launch beta 8's app chooses for the model (the same flags
and env for both); one request per server (`/v1/chat/completions`, 128 tokens out, temperature 0,
`cache_prompt: false`); two servers per side alternating ToshLLM / beta 8 for the short prompt; the
long prompt (2543 tokens on the 14B, 2465 on gemma) on one server per side only. Values: the server's
own `prompt_per_second` / `predicted_per_second` for that request (N=1 per server; not benchmarks).
The 35B got the short prompt only (ToshLLM's unbounded command buffers).

| model and launch | prompt | ToshLLM prompt / decode tok/s | beta 8 prompt / decode tok/s |
|---|---|---|---|
| Qwen3-14B Q4_K_M, tensor split over both cards, `-c 16384 -ub 128 -b 128 -fa auto` | 513 | 42.24 / 8.05, 42.20 / 8.06 | 46.13 / 10.00, 46.51 / 10.03 |
| | 2543 | 41.22 / 7.77 | 46.58 / 9.48 |
| gemma4 12B Q8_0 (12.7 GB) in RAM, `-ngl 0 -c 8192 -fa auto`, card 1 visible | 503 | 10.96 / 2.60, 11.01 / 2.56 | 18.78 / 3.31, 18.81 / 3.32 |
| | 2465 | 9.70 / 1.97 | 20.09 / 3.02 |
| Ornith-1.0-35B Q6_K (28.5 GB), `-ngl 99 -c 32768 -fa 1 --dynamic-moe on`, both cards | 513 | 35.63 / 4.23, 35.96 / 4.23 | 62.62 / 13.67, 63.89 / 14.05 |

Text: the 14B and gemma answers are byte-identical across all four servers at the short prompt and
between the two engines at the long prompt. On the 35B three answers are identical and one beta 8 answer
differs from character 208 (dynamic MoE places experts differently run to run; beta 8 ticket 26). The
128-token cap ends every answer inside the model's reasoning, so this compares speed, not answer quality.

Seen in the logs: ToshLLM 0.87.33 logs `failed to create pipeline state` for its AMD flash-attention
kernels (`kernel_flash_attn_ext_{vec,pf}_amd_dk128...`, 324 per 14B short-prompt run, 1604 for the long
prompt; `..._dk256...` 12 per 35B run); beta 8 logs none. Neither engine printed an `op offload on/off`
line on these launches, so this report does not attribute gemma's prompt rate to beta 8's prompt
offload; the cause of that gap is not measured here.

## Not covered

- ToshLLM's own app launch (its placement and defaults) — it cannot run without touching the user's data.
- Decode at depth 4096 and prompts past ~2.5k tokens: ToshLLM's engine has no command-buffer bound.
- Answer quality: 128 tokens end inside the reasoning.
