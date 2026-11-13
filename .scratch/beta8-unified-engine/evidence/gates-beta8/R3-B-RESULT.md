# R3-B — stress group B (14B, Nemotron-3.5-Bolt-E4B, Ternary-Bonsai-2-27B-PQ2_0) + ngl0nopo check

Script: `.scratch/beta8-unified-engine/evidence/gates-beta8/stress-set.sh` (prepared; run unchanged,
no source or script edited). Set: `STRESS_MODELS="Qwen3-14B-Q4_K_M Nemotron-3.5-Bolt-E4B-Q4_K_M
Ternary-Bonsai-2-27B-PQ2_0"`. Log: `stress-B.log`. Engine: `dist/XeonLLM.app/Contents/Resources/bin/llama-server`,
`sha256` prefix `63eb2a01af361672`, banner in every server log `XeonLLM engine 0.87.31-beta.8 (app standalone)`.
App launch per model came from `testapp.sh` (`dev.xeonllm.gatetest`, `XeonLLMGateTest`, port 18099), saved as `out/set/<stem>.applog`.

## Health and times

- Before: `ls -t /Library/Logs/DiagnosticReports/ | head -3` →
  `XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag`, `XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag`,
  `XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag`.
- After `### done`: identical three names, no new `*.panic` / `*watchdog*` / `*.gpuRestart` file name.
- Start `### Qwen3-14B-Q4_K_M 06:00`, end `### done`, `stress-B.log` mtime `Nov 13 08:08:42 2026`
  (2 h 08 min; under the 3 h stop).
- One server at a time; nothing else heavy ran alongside. Port 8080 (pid 747) and `/Applications/XeonLLM.app` untouched.
- Nothing could not be run in this group; all 9 model/mode runs finished.

## Per model

### Qwen3-14B-Q4_K_M

App launch lines from `stress-B.log` (and `out/set/Qwen3-14B-Q4_K_M.applog`):

```
 == Qwen3-14B-Q4_K_M
 placement: card
 context: 32768 -> 16384 (f16 KV, 2 cards, 6144 MiB each: the requested context does not fit)
 args: -m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf -ngl 99 -c 16384 -t 12 -fa auto --host 127.0.0.1 --port 18099 --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode tensor -n 2048 --path .../web-ui --ui-config {...}
 env: GGML_METAL_DEVICES=2 TOSH_FA_AMD=1 TOSH_MGPU_EVENTS=1
 dflash : not installed
```

`n_ctx_slot = 16384` in all three of its server logs (the app's ctx-fit launch at a saved 32768).
Modes: tensor port 56554, layer 56982, ngl0 57681.

cells.tsv lines:

```
-- Qwen3-14B-Q4_K_M-tensor.cells.tsv:   20 PASS    1 SKIP
-- Qwen3-14B-Q4_K_M-layer.cells.tsv:   20 PASS    1 SKIP
-- Qwen3-14B-Q4_K_M-ngl0.cells.tsv:    3 PASS
```

Only non-PASS: `parallel2	SKIP	--parallel 1 does not allow it` (tensor and layer). `over-ctx` is
`PASS	refused with 400 at n_ctx=16384` both GPU modes; `cancel-stream` `PASS	stream closed after 64 bytes`.

identical / drafter lines:

```
Qwen3-14B-Q4_K_M.gguf	layer	identical-vs-tensor	PASS	band16 band300 band1100 byte-identical	0
Qwen3-14B-Q4_K_M.gguf	tensor	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Qwen3-14B-Q4_K_M.gguf	layer	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Qwen3-14B-Q4_K_M.gguf	ngl0	identical-vs-previous	FAIL	band300 differs at offset 6	0
Qwen3-14B-Q4_K_M.gguf	tensor	identical-vs-ngl0	DIFFERS	band300 differs at offset 6	0
Qwen3-14B-Q4_K_M.gguf	layer	identical-vs-ngl0	DIFFERS	band300 differs at offset 6	0
```

No `draft` mode in this set, so no `drafter-head` row (no `<stem>.dflash.gguf` beside it either).
`ngl0` vs beta.7's ngl0: `ngl0: "Okay, let's see. The user provided a long text"` against
`layer: 'Okay, the user provided a long text that repea'` (band300; `answers.json` texts, first difference at char 6).

Answers (tensor mode, first 100 chars; full text is reasoning then `\n--\n` then content):

| cell | first 100 chars | on topic |
|---|---|---|
| band16 | `Okay, let's see. The user provided a text that repeats the sentence about the quick brown fox and th` | yes |
| band4200 | `Okay, the user provided a long text that repeats the same sentence multiple times, mentioning the qu` | yes |
| band8300 | `Okay, the user provided a long text that repeats the same sentence multiple times, mentioning the qu` | yes |
| tools | `Okay, the user is asking for the weather in Lisbon and wants me to use the tool. Let me check the av` | yes |

Tools cell: `PASS	prompt_tokens=156 completion_tokens=100`; prose names `get_weather`, `city`, `Lisbon`
(`I need to call that function with the city set to Lisbon.`). The script keeps no `tool_calls` payload
(`scripts/stress-release.sh:200-204`), so name + arguments are not in the evidence.

### Nemotron-3.5-Bolt-E4B-Q4_K_M

```
 == Nemotron-3.5-Bolt-E4B-Q4_K_M
 placement: card
 context: 32768 -> 31744 (f16 KV, 2 cards, 6144 MiB each: the requested context does not fit)
 args: -m /Users/sam/models/Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf -ngl 99 -c 31744 -t 12 -fa auto --host 127.0.0.1 --port 18099 --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode tensor -n 2048 -md /Users/sam/models/Nemotron-3.5-Bolt-E4B-Q4_K_M.dflash.gguf --spec-type draft-dflash -ngld 6 -ctkd q8_0 -ctvd q8_0 --path .../web-ui --ui-config {...}
 env: GGML_METAL_DEVICES=2 TOSH_FA_AMD=1 TOSH_MGPU_EVENTS=1
 dflash : auto, ngld=6 (estimated 10.4 / 10.5 GiB budget)
```

The app's own launch loads a drafter (`-md ... -ngld 6`); `stress-release.sh` drops `-m/-md`, so the
stress run itself has no drafter and there is no `draft` mode row for it here.

`n_ctx_slot = 31744` in all three logs. tensor 57878, layer 58101, ngl0 58371.

```
-- Nemotron-3.5-Bolt-E4B-Q4_K_M-tensor.cells.tsv:   20 PASS    1 SKIP
-- Nemotron-3.5-Bolt-E4B-Q4_K_M-layer.cells.tsv:   20 PASS    1 SKIP
-- Nemotron-3.5-Bolt-E4B-Q4_K_M-ngl0.cells.tsv:    3 PASS
```

Only non-PASS: `parallel2	SKIP	--parallel 1 does not allow it` (both GPU modes). `over-ctx`
`PASS	refused with 400 at n_ctx=31744`; `cancel-stream` `PASS	stream closed after 64 bytes`.

```
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	layer	identical-vs-tensor	PASS	band16 band300 band1100 byte-identical	0
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	tensor	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	layer	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	ngl0	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	tensor	identical-vs-ngl0	DIFFERS	band1100 differs at offset 0	0
Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf	layer	identical-vs-ngl0	DIFFERS	band1100 differs at offset 0	0
```

This is the one model of group B whose ngl0 text still matches beta.7 byte for byte.
`identical-vs-ngl0` band1100: ngl0 starts `1.  **Analyze the request:** The user wa`, layer starts
`Thinking Process:\n\n1.  **Analyze the Req` (first difference at offset 0).

Answers (tensor):

| cell | first 100 chars | on topic |
|---|---|---|
| band16 | `Thinking Process:\n1.  **Analyze the request:** The user wants me to act as a terse assistant, read t` | yes |
| band4200 | `1.  **Analyze the Request:** The user wants me to act as a terse assistant, read a very long, repeti` | yes |
| band8300 | `1.  **Analyze the Request:** The user wants me to act as a terse assistant, read a very long, repeti` | yes |
| tools | `1. **Analyze the user request:** The user is asking for the weather in "Lisbon" and explicitly instr` | yes |

Tools cell `PASS	prompt_tokens=68 completion_tokens=144`; prose: `**Construct the tool call:** get_weather(city="Lisbon")`.
No `tool_calls` payload in the evidence (same script limitation).

### Ternary-Bonsai-2-27B-PQ2_0

```
 == Ternary-Bonsai-2-27B-PQ2_0
 placement: card
 args: -m /Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -c 32768 -t 12 -fa auto --host 127.0.0.1 --port 18099 --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode layer -n 2048 --path .../web-ui --ui-config {...}
 env: GGML_METAL_DEVICES=2 TOSH_FA_AMD=1 TOSH_MGPU_EVENTS=1
 dflash : off by memory planner (need 10.66 GiB, budget 10.5 GiB)
```

The app saved `--split-mode layer` for this model (`placement: card`, no `context:` line: ctx not lowered,
`n_ctx_slot = 32768` in all three stress logs). The script ran tensor, layer and ngl0 regardless.

```
-- Ternary-Bonsai-2-27B-PQ2_0-tensor.cells.tsv:   20 PASS    1 SKIP
-- Ternary-Bonsai-2-27B-PQ2_0-layer.cells.tsv:   20 PASS    1 SKIP
-- Ternary-Bonsai-2-27B-PQ2_0-ngl0.cells.tsv:    3 PASS
```

Only non-PASS: `parallel2	SKIP	--parallel 1 does not allow it`. `over-ctx`
`PASS	refused with 400 at n_ctx=32768`; `cancel-stream` `PASS	stream closed after 64 bytes`.

```
Ternary-Bonsai-2-27B-PQ2_0.gguf	layer	identical-vs-tensor	PASS	band16 band300 band1100 byte-identical	0
Ternary-Bonsai-2-27B-PQ2_0.gguf	tensor	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Ternary-Bonsai-2-27B-PQ2_0.gguf	layer	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
Ternary-Bonsai-2-27B-PQ2_0.gguf	ngl0	identical-vs-previous	FAIL	band300 differs at offset 226	0
Ternary-Bonsai-2-27B-PQ2_0.gguf	tensor	identical-vs-ngl0	DIFFERS	band300 differs at offset 226	0
Ternary-Bonsai-2-27B-PQ2_0.gguf	layer	identical-vs-ngl0	DIFFERS	band300 differs at offset 226	0
```

`identical-vs-ngl0` band300: layer `...Likely blue. Need be terse...`, ngl0 `...Likely "blue". Need be terse...`
(first difference at offset 226).

Answers (tensor):

| cell | first 100 chars | on topic |
|---|---|---|
| band16 | `We need answer user's request. User: "You are a terse assistant. Read the text and answer the final ` | yes |
| band4200 | `We need answer user's final question. User: "You are a terse assistant. Read the text and answer the` | yes |
| band8300 | `We need answer user's final question. User: "You are a terse assistant. Read the text and answer the` | yes |
| tools | `The user is asking about the weather in Lisbon and explicitly requesting to use the tool. I should c` | yes |

Tools cell `PASS	prompt_tokens=315 completion_tokens=62`; prose: `I should call the get_weather function with city="Lisbon".`
No `tool_calls` payload in the evidence.

## grep counts over the model's server logs (9 logs of this group)

`kernel not found`, `exited with code`, `GGML_ASSERT`, `GGML_ABORT`, `failed to create pipeline`,
`TEXT BAD`, `@@@@`, `kIOAccel`, `op offload`, `prompt offload`: **0 in every log** (GPU and ngl0).

Driver-refusal fallback lines (handled by the shipped fallback, not `kernel not found`):

| log | `the driver refused` count |
|---|---|
| 14B tensor | 3 (`kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16_w64_lg16`, `..._vec_amd_dk128_..._w64`, `..._vec_amd_dk128_..._w64_wg32`) |
| 14B layer | 2 (pf lg16, vec w64) |
| 14B ngl0 | 0 |
| Nemotron tensor | 4 (`pf_amd_dk256_..._lg16`, `vec_amd_dk256_..._w64`, `vec_amd_dk512_..._w64`, `vec_amd_dk512_..._w64_wg32`) |
| Nemotron layer | 4 (same four) |
| Nemotron ngl0 | 0 |
| Ternary tensor | 3 (`pf_amd_dk256_..._lg16`, `vec_amd_dk256_..._w64`, `vec_amd_dk256_..._w64_wg32`) |
| Ternary layer | 3 (same three) |
| Ternary ngl0 | 0 |

## The ngl0nopo run (after `### done`)

Why: `ngl0 identical-vs-previous` fails in group A for 0.6B (band1100), 4B Q4/Q6 (band1100) and 8B
(band16), and in group B for 14B (band300) and Ternary-Bonsai (band300). Suspected cause named in the
brief: core/0082 offloads the prompt to a card at `-ngl 0`. Test: `-ngl 0 --no-op-offload`, `MODES=ngl0nopo`,
`NGL0_CELLS="band16 band300 band1100"`, one model at a time.

Times: `### Qwen3-8B-Q4_K_M 08:17:32` → `rc=0 08:20:25`; `### Qwen3-0.6B-Q8_0 08:20:25` → `rc=0 08:21:13`.
DiagnosticReports before and after both runs: the same three names, no new panic/watchdog/gpuRestart.

`nopo` cells (both models, 3 PASS each):

```
Qwen3-8B-Q4_K_M.gguf	ngl0nopo	band16	PASS	prompt_tokens=80 completion_tokens=64 14.3s	80
Qwen3-8B-Q4_K_M.gguf	ngl0nopo	band300	PASS	prompt_tokens=448 completion_tokens=64 35.3s	448
Qwen3-8B-Q4_K_M.gguf	ngl0nopo	band1100	PASS	prompt_tokens=1483 completion_tokens=64 91.5s	1483
Qwen3-0.6B-Q8_0.gguf	ngl0nopo	band16	PASS	prompt_tokens=80 completion_tokens=64 2.0s	80
Qwen3-0.6B-Q8_0.gguf	ngl0nopo	band300	PASS	prompt_tokens=448 completion_tokens=64 4.8s	448
Qwen3-0.6B-Q8_0.gguf	ngl0nopo	band1100	PASS	prompt_tokens=1483 completion_tokens=64 12.7s	1483
```

The script's own comparison rows for this mode (from `out/set-nopo/<stem>/tables/raw.tsv`) are all SKIP,
because `MODES` contained only `ngl0nopo` (no `ngl0`/`tensor` run of this model in that OUT) and the
PREV_OUT path was doubled (`/Users/sam/firellama//Users/sam/firellama/...`), so the comparison below was
done outside the script, on the saved `*-ngl0nopo.answers.json` against `gates-beta7/out2/set/<stem>/*-ngl0.answers.json`
and `out/set/<stem>/*-ngl0.answers.json`, key by key, character by character.

| model | band | nopo vs beta.7 ngl0 | nopo vs beta.8 ngl0 |
|---|---|---|---|
| Qwen3-8B-Q4_K_M | band16 | differs at offset 225 (both len 282) | identical (len 282) |
| Qwen3-8B-Q4_K_M | band300 | identical (len 278) | identical (len 278) |
| Qwen3-8B-Q4_K_M | band1100 | identical (len 294) | identical (len 294) |
| Qwen3-0.6B-Q8_0 | band16 | identical (len 265) | identical (len 265) |
| Qwen3-0.6B-Q8_0 | band300 | identical (len 268) | identical (len 268) |
| Qwen3-0.6B-Q8_0 | band1100 | differs at offset 216 (nopo 262, beta.7 268) | identical (len 262) |

First-difference texts:

- 8B band16: nopo `t, I need to check if there's any mention of the sky's color in the gi` against
  beta.7 `t, I need to check if the text gives any clues about the sky's color. `
- 0.6B band1100: nopo ` word.\n\nFirst, I need to check if there's any mention of the sky in\n--` against
  beta.7 ` word.\n\nFirst, I need to look through the text to find any mention of `

`--no-op-offload` reproduces beta 8's ngl0 text exactly for all six cells, and only two of the six
match beta.7 byte for byte. No line in any of the nine beta 8 ngl0 logs contains `op offload` (count 0
in each), so the run does not show the op offload was on at `-ngl 0` to begin with; what the six cells
do show is that the switch changed no text on these models. The remaining CPU-text differences against
beta.7 are therefore unattributed to op offload (any other change in the beta.8 series, or the launch
flags, could produce them). Prompt rate also does not separate the two 8B runs: `prompt eval time`
for the 80-, 384- and 1051-token prompts is `6639.60 / 27534.95 / 81056.92 ms` (beta 8 ngl0) against
`6761.41 / 27344.84 / 81952.37 ms` (`ngl0nopo`).

`op offload` / `prompt offload` lines in beta 8's ngl0 server logs of `out/set/`: **0 occurrences** in all
nine (`Qwen3-14B-Q4_K_M`, `Nemotron-3.5-Bolt-E4B-Q4_K_M`, `Ternary-Bonsai-2-27B-PQ2_0`, `Qwen3-8B-Q4_K_M`,
`Qwen3-0.6B-Q8_0`). `vendor/llama.cpp/src/llama-context.cpp:817` only prints when `cparams.op_offload && !no_alloc` **and** a
GPU backend is in `backend_ptrs`; with `-ngl 0` the card is not a backend (ngl0 logs have `ggml_metal: device 0`
probe lines only from the engine's own probe, no `device 1`, and the ngl0 env file is `TOSH_FA_AMD=1` only,
`GGML_METAL_DEVICE_LIST` dropped). `-ngl 0 --no-op-offload` also prints nothing, and its ngl0nopo server log
holds the same single CPU compute-buffer line (`CPU compute buffer size of  39.3794 MiB, does not match
expectation of  36.0044 MiB` for 8B, both runs).

Note, not part of the brief: every `-ngl 0` run logs
`W DEPRECATED: argument '-ngl' specified multiple times` (`arg.cpp:856`; the app's args carry `-ngl 99`,
the script appends `-ngl 0`, only the last wins). GPU modes do not log it.

## Verdict

9/9 model/mode runs in group B completed: 20 PASS / 1 SKIP (parallel2, `--parallel 1`) on tensor and
layer, 3 PASS on `-ngl 0`; no FAIL, no REFUSED, no new DiagnosticReport, and 0 `kernel not found` /
`exited with code` / `GGML_ASSERT` / `GGML_ABORT` / `failed to create pipeline` / `TEXT BAD` / `@@@@`.
The only gated failures are `ngl0 identical-vs-previous` (14B band300 offset 6, Ternary band300 offset
226); Nemotron's ngl0 matches beta.7. `ngl0nopo` matches beta 8's ngl0 exactly for all six cells, so
op offload does not explain the remaining CPU-text differences against beta.7.