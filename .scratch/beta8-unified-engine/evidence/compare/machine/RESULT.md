# Whole-machine comparison — XeonLLM 0.87.31-beta.8 vs ToshLLM 0.87.33

Measurement only. No source edited, nothing built, no app launched, no defaults domain touched, no write into either Application Support folder, pid 747 / port 8080 untouched. 2026-11-13 20:38–21:14 CET. 64 GB RAM Mac, two AMD Radeon HD FirePro D700 (card 0 = display), 24 logical CPUs, Darwin x86_64.

Harness: `.scratch/beta8-unified-engine/evidence/compare/machine/run.sh` — one server at a time, foreground under `perl -e 'alarm 1800; exec @ARGV'`, polled `/health` (10 s × up to 60), one `POST /v1/chat/completions` (`max_tokens:128, temperature:0, cache_prompt:false`), then kill + wait, then the DiagnosticReports check. No flags were rejected by either engine, so no rerun without a flag was needed (one extra ToshLLM M1 512 run with `TOSH_FA_AMD=0` was made only to attribute the Metal FA pipeline-compile errors; kept as `m1-t1-faoff-*`).

All speeds below are verbatim `timings.prompt_per_second` / `timings.predicted_per_second` and `usage.prompt_tokens` from the saved response JSON.

## M1 — Qwen3-14B-Q4_K_M, tensor split, both cards

| prompt | metric | t1 | t2 | x1 | x2 | verdict |
|---|---|---|---|---|---|---|
| prompt-512 (prompt_tokens 513) | prompt t/s | 42.2424047045 | 42.2024964628 | 46.1340020995 | 46.5099242931 | X above |
| prompt-512 | decode t/s | 8.0472922256 | 8.0562169160 | 10.0031285375 | 10.0290993924 | X above |
| prompt-2048 (prompt_tokens 2543) | prompt t/s | 41.2231770934 | — (t2 not run) | 46.5788750423 | — (x2 not run) | overlap (n=1 per side) |
| prompt-2048 | decode t/s | 7.7718859675 | — | 9.4795750613 | — | overlap (n=1 per side) |

Text identical across t1/t2/x1/x2 at 512 (content + reasoning_content, Python exact: all True, no first differing offset). At 2048 also identical between t1 and x1. All four 512 responses have empty `content` and 550 chars in `reasoning_content` — `finish_reason: length`: the 128 generated tokens are all reasoning, no final answer text, so there is no x1 "answer" to quote. First 100 chars of x1's `reasoning_content`:
`Okay, so I need to summarize the history of Lisbon based on the provided text. Let me read through the text a` — on topic (it is reasoning toward the Lisbon summary, but not a summary).

Load lines: no `op offload on:` / `op offload off:` line in any log, on either engine (`grep -c` = 0 in all 12 M1 logs). ToshLLM 0.87.33 only: 324 `ggml_metal_library_compile_pipeline: failed to create pipeline state` errors per 512 run (1604 for the 2543-token run) for `kernel_flash_attn_ext_{vec,pf}_amd_dk128_kf16_vf16*`; XeonLLM beta 8: 0. The errors persist with `TOSH_FA_AMD=0` (`m1-t1-faoff.log`, also 324), so the env flag is not what switches them.

Method: engine sha256 XeonLLM `63eb2a01af36…`, ToshLLM `f3e4ec060b77…`; both report `version: 0.6.0-dev (build 11429, commit d81235049)`, XeonLLM built with AppleClang 21.0.0.21000101, ToshLLM with AppleClang 17.0.0.17000013. Models: Qwen3-14B-Q4_K_M.gguf (9 001 753 376 B). env `TOSH_AUTO_KV=auto TOSH_FA_AMD=1 GGML_METAL_DEVICE_LIST=0,1`. Flags: `-m … -ngl 99 -c 16384 -t 12 -fa auto --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode tensor -n 2048 --host 127.0.0.1 --port 18130`. N = 2 server processes per side alternating (t1 x1 t2 x2), one request per server per prompt, 512 first; 2048 run as a separate pass (t1 x1) because the 2048 file is 2543 tokens, over the ~2048 ceiling. `cache_prompt` false. `threadpool n_threads = 12` on both sides. Prompt limits: 512 / 2048 request files (they tokenize to 513 / 2543) chosen because ToshLLM 0.87.33 has no command-buffer time bound and this Mac has frozen/panicked on long GPU command buffers; the 2048 ceiling on the 14B and gemma and the 512 ceiling on the 35B were not raised.

## M2 — gemma-4 12B Q8_0, RAM only (`-ngl 0`), card 1 visible

| prompt | metric | t1 | t2 | x1 | x2 | verdict |
|---|---|---|---|---|---|---|
| prompt-512 (prompt_tokens 503) | prompt t/s | 10.9592135546 | 11.0102425025 | 18.7761882098 | 18.8084857905 | X above |
| prompt-512 | decode t/s | 2.5994118452 | 2.5627370645 | 3.3060941546 | 3.3150204988 | X above |
| prompt-2048 (prompt_tokens 2465) | prompt t/s | 9.7010167496 | — | 20.0932782963 | — | overlap (n=1 per side) |
| prompt-2048 | decode t/s | 1.9669100984 | — | 3.0170094718 | — | overlap (n=1 per side) |

Text identical across all four 512 runs and between t1/x1 at 2048 (exact, no offset). All responses have empty `content` (reasoning only, `finish_reason: length`), so x1 has no answer text to quote; its reasoning starts `A single paragraph summarizing the history of Lisbon from Phoenician settlement (1200 BCE) through Rom…` — on topic.

Load lines: no `op offload on:` / `op offload off:` line on either engine (0 matches in all 8 M2 logs). Only XeonLLM beta 8 prints, per 512 run:
`W ggml_metal_op_flash_attn_ext: the driver refused kernel_flash_attn_ext_pf_amd_dk256_kf16_vf16_w64_lg16; the tile kernel takes the prefill`
`W ggml_metal_op_flash_attn_ext: kernel_flash_attn_ext_pf_amd_dk256_kf16_vf16 is not available on this card; the tile kernel takes the prefill`
`W ggml_metal: MTL0: one node of a 491-token batch averages 99.1 ms, over the 50 ms command-buffer target; use a smaller ubatch`
(2048 run: `… 512-token batch averages 98.8 ms …`). ToshLLM prints none of these.

Method: same binaries/shas/versions/model file `gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0.gguf` (12 669 645 344 B). env `TOSH_FA_AMD=1 GGML_METAL_DEVICE_LIST=1`. Flags: `-m … -ngl 0 -c 8192 -t 12 -fa auto --load-mode none --jinja --metrics --cache-ram 0 --parallel 1 -n 2048 --host 127.0.0.1 --port 18130`. N = 2 per side alternating, one request each per prompt, 512 first; 2048 pass separate (t1 x1) for the same 2048-ceiling reason; `threadpool n_threads = 12` on both sides; `cache_prompt` false.

## M3 — Ornith-1.0-35B Q6_K, dynamic MoE, both cards

| prompt | metric | t1 | t2 | x1 | x2 | verdict |
|---|---|---|---|---|---|---|
| prompt-512 (prompt_tokens 513) | prompt t/s | 35.6306043971 | 35.9634560811 | 62.6213976217 | 63.8857399183 | X above |
| prompt-512 | decode t/s | 4.2326496193 | 4.2292349227 | 13.6748411350 | 14.0533736064 | X above |
| prompt-2048 | — | not run | — | not run | — | see below |

Text: t1 = t2 = x2 exactly (content + reasoning, no offset). x1 differs from them at offset 208 of the concatenated content+reasoning string (empty content + 464-char reasoning vs 487-char reasoning; same first 208 chars). All four have empty `content`; x1's reasoning starts `Here's a thinking thinking sequence\n\n1.  **Deconstruct and Analyze the Text:**\n    *   *Segment 1:* "The history of Lisbon...` — on topic.

Load lines, verbatim. ToshLLM t1 and t2 (identical):
`I Tosh Dynamic MoE: mode=PLAN_FULL_HOST_DMOE reason=FULL_HOST_SAFE warnings=COVERAGE_CONSTRAINED rss=30.1GiB vram=4.6GiB warm=0.0GiB hot=2.3GiB coverage=1.10 CONSTRAINED ctx=32768 kv=f16 ub=512`
`W llama_tosh_dmoe_budget: under 788 MiB left for experts, mixed execution stays off`
XeonLLM x1:
`I Tosh Dynamic MoE: mode=PLAN_FULL_HOST_DMOE reason=FULL_HOST_SAFE warnings=COVERAGE_CONSTRAINED rss=28.8GiB vram=9.6GiB warm=0.0GiB hot=4.2GiB coverage=1.17 CONSTRAINED ctx=32768 kv=f16 ub=1024`
(no `llama_tosh_dmoe_budget` line)
XeonLLM x2: same line as x1 except the leading timestamp (`… rss=28.8GiB vram=9.6GiB warm=0.0GiB hot=4.2GiB coverage=1.17 CONSTRAINED ctx=32768 kv=f16 ub=1024`), no `llama_tosh_dmoe_budget` line.
No `op offload on:` / `op offload off:` line on either side. ToshLLM also logs 12 `failed to create pipeline state` errors per 512 run for `kernel_flash_attn_ext_{vec,pf}_amd_dk256_kf16_vf16*`; XeonLLM logs 0 and instead logs `W ggml_metal_op_flash_attn_ext: the driver refused kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64; using kernel_flash_attn_ext_vec_amd_dk256_kf16_vf16_w64_lds32` plus `ggml_cpu: multi-row dot ON for q6_K (AVX1)`.

Method: model `Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf` (28 514 152 288 B). env `TOSH_AUTO_KV=auto TOSH_FA_AMD=1 GGML_METAL_DEVICE_LIST=0,1`. Flags: `-m … -ngl 99 -c 32768 -t 12 -fa 1 --dynamic-moe on --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 -n 2048 --host 127.0.0.1 --port 18130`. N = 2 per side alternating (t1 x1 t2 x2), 512 only. Both engines clamp the threadpool to `n_threads = 2` on this model despite `-t 12` (logged identically on all four runs), so the CPU decode share is 2 threads on both sides.

## Not run, and why

- M3 prompt-2048: not run. 512 only per the task (ToshLLM 0.87.33 has no command-buffer time bound; the 35B decode is already the heaviest GPU path and a 2048-token prompt on it was explicitly capped out).
- M1 and M2 `t2`/`x2` at 2048: not run (single pass each); the 2048 files are 2543 / 2465 prompt tokens, past the ~2048 limit, so only one server per side was exposed to them.
- No `temperature` other than 0, no other `max_tokens`, no `cache_prompt:true`, no `-fa 0` comparison for M1/M2 beyond the one ToshLLM attribution run (`m1-t1-faoff-*`), no app launch, no Metal device-list variation, no `-ngl` variation for gemma, no repeat of the M3 run that differed (x1).
- Not measured: power, temperature, RAM bandwidth, wall-clock of load-to-health beyond the `/health` poll, any 8080 pid-747 server.

## Files

`<model>-<label>-p<N>.json` — full responses. `<model>-<label>[-2048|-faoff].log` — server logs. `run.sh` — harness. `prompt-512.txt`, `prompt-2048.txt` — prompts (one English paragraph on the history of Lisbon, repeated to reach ~512 / ~2048 tokens, then `Summarize the text above in three sentences.`). `diag-first.txt`, `diag-now.txt`, `appsupport-before.txt`, `appsupport-after.txt`.