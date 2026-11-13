# R3-A — the stress test of the shipped app's real launch (contract §4)

Script: `.scratch/beta8-unified-engine/evidence/gates-beta8/stress-set.sh` (prepared; run unchanged, no
source or script edited). Set: `STRESS_MODELS="Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K
Qwen3-8B-Q4_K_M LFM3-1.7B-F16"`. Log: `stress-A.log`.

Method: per model the test app (`dev.xeonllm.gatetest`, `XeonLLMGateTest`, tensor split, saved ctx
32768) launched the model once and its server log was kept as `out/set/<stem>.applog`;
`scripts/stress-release.sh` then drove `dist/XeonLLM.app/Contents/Resources/bin/llama-server`
(sha256 prefix `63eb2a01af361672`, engine banner `XeonLLM engine 0.87.31-beta.8 (app standalone)` in
every server log) with those flags, modes `tensor layer ngl0`, `NGL0_CELLS="band16 band300 band1100"`,
`PREV_OUT=.../gates-beta7/out2/set/<stem>`.

Start 04:00 (log line `### Qwen3-0.6B-Q8_0 04:00`), end 05:38 (`### done`, `stress-A.log` mtime
05:38:33). Wall clock 1 h 38 min; no 3 h stop was needed.

## Health

- `ls -t /Library/Logs/DiagnosticReports/ | head -3` before and after: identical names both times
  (`XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag`,
  `XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag`,
  `XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag`). No new `*.panic` / `*watchdog*` / `*.gpuRestart`.
- One server at a time (the script's own sequencing); nothing else heavy was run.
- Port 8080 (pid 747) and `/Applications/XeonLLM.app` untouched.

## The app launch (per model, from `stress-A.log`)

All five: `placement: card`, `dflash : not installed` (from `<stem>.applog`), `env:
GGML_METAL_DEVICES=2 TOSH_FA_AMD=1 TOSH_MGPU_EVENTS=1` (LFM3 has no `TOSH_MGPU_EVENTS`), ctx not
lowered — `n_ctx_slot = 32768` in every server log.

- Qwen3-0.6B-Q8_0 — `placement: card`; `args: -m /Users/sam/models/Qwen3-0.6B-Q8_0.gguf -ngl 99 -c 32768 -t 12 -fa auto --host 127.0.0.1 --port 18099 --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 204`; modes tensor 52166, layer 52259, ngl0 52404.
- Qwen3-4B-Q4_K_M — `placement: card`; same args with `-m .../Qwen3-4B-Q4_K_M.gguf ... --cache-ram 204`; tensor 52454, layer 52734, ngl0 53163.
- Qwen3-4B-Q6_K — `placement: card`; `--cache-ram 2048 `; tensor 53250, layer 53545, ngl0 54045.
- Qwen3-8B-Q4_K_M — `placement: card`; `--cache-ram 204`; tensor 54131, layer 54466, ngl0 55005.
- LFM3-1.7B-F16 — `placement: card`; `--cache-ram 2048 `; tensor 55123, layer 55318, ngl0 55526.

## cells.tsv summaries (script's own lines, from `stress-A.log`)

| stem | tensor | layer | ngl0 |
|---|---|---|---|
| Qwen3-0.6B-Q8_0 | `-- Qwen3-0.6B-Q8_0-tensor.cells.tsv:   20 PASS    1 SKIP ` | `-- Qwen3-0.6B-Q8_0-layer.cells.tsv:   20 PASS    1 SKIP ` | `-- Qwen3-0.6B-Q8_0-ngl0.cells.tsv:    3 PASS ` |
| Qwen3-4B-Q4_K_M | `20 PASS    1 SKIP ` | `20 PASS    1 SKIP ` | `3 PASS ` |
| Qwen3-4B-Q6_K | `20 PASS    1 SKIP ` | `20 PASS    1 SKIP ` | `3 PASS ` |
| Qwen3-8B-Q4_K_M | `20 PASS    1 SKIP ` | `20 PASS    1 SKIP ` | `3 PASS ` |
| LFM3-1.7B-F16 | `20 PASS    1 SKIP ` | `20 PASS    1 SKIP ` | `3 PASS ` |

Non-PASS cells, every one (quoted from `tables/stress.tsv` / `cells.tsv`):

- `parallel2	SKIP	--parallel 1 does not allow it	0` — every model, tensor and layer. The app
  launches at `--parallel 1` (`parallelSlots: Int = 1`, `Sources/Servers/Server.swift:76`), so the
  contract's "two concurrent requests where `--parallel` allows it" does not apply to this launch.

That is the only non-PASS in the whole run: no FAIL, no REFUSED. `over-ctx` in every cell is
`PASS	refused with 400 at n_ctx=32768`; `cancel-stream` `PASS	stream closed after 64 bytes`.

## Identical / drafter lines (quoted)

- **layer vs tensor (gated).** All five: `identical-vs-tensor	PASS	band16 band300 band1100 byte-identical`
  (tensor and layer rows both).
- **vs the beta.7 text (PREV_OUT), gated.**
  - Qwen3-0.6B-Q8_0: `tensor identical-vs-previous	PASS`, `layer identical-vs-previous	PASS`, `ngl0 identical-vs-previous	FAIL	band1100 differs at offset 216`.
  - Qwen3-4B-Q4_K_M: `tensor PASS`, `layer PASS`, `ngl0 FAIL	band1100 differs at offset 143`.
  - Qwen3-4B-Q6_K: `tensor PASS`, `layer PASS`, `ngl0 FAIL	band1100 differs at offset 51`.
  - Qwen3-8B-Q4_K_M: `tensor PASS`, `layer PASS`, `ngl0 FAIL	band16 differs at offset 225`.
  - LFM3-1.7B-F16: `tensor identical-vs-previous	SKIP	no tensor run in /Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta7/out2/set/LFM3-1.7B-F16`, `layer PASS`, `ngl0 SKIP	no ngl0 run in ...`.

  The `ngl0` FAIL rows are the CPU mode against the previous release's CPU mode, and they are the
  script's only gated comparison that fails; the GPU (tensor, layer) rows match beta.7 byte for byte.
  In beta.7 the LFM3 tensor and ngl0 runs never produced answers at all
  (`LFM3-1.7B-F16-tensor.server.log`: `LLAMA_SPLIT_MODE_TENSOR not implemented for architecture
  'lfm3'`; `tables/stress.tsv`: `ngl0	FAIL	server did not start`), so those two are SKIP, and the
  beta.7 layer text matches beta.8's byte for byte.

- **GPU vs `-ngl 0`, reported only.** tensor and layer `identical-vs-ngl0`:
  Qwen3-0.6B-Q8_0 `DIFFERS	band1100 differs at offset 216`; Qwen3-4B-Q4_K_M `DIFFERS	band1100
  differs at offset 143`; Qwen3-4B-Q6_K `DIFFERS	band1100 differs at offset 163`; LFM3-1.7B-F16
  `PASS	band16 band300 band1100 byte-identical` (both rows); Qwen3-8B-Q4_K_M `PASS	band16 band300
  band1100 byte-identical` (both rows).
- **drafter.** No `draft` mode was in this set (`MODES="tensor layer ngl0"` for every model here), so
  no `drafter-head` row exists in any of these five runs, and no model in this set has a
  `<stem>.dflash.gguf` beside it (`dflash : not installed` in each applog). Nothing to report.

## Answers (tensor mode; first 100 chars, `*-tensor.answers.json`)

| stem | cell | first 100 chars | on topic (my reading) |
|---|---|---|---|
| Qwen3-0.6B-Q8_0 | band16 | `Okay, let's see. The user provided a text that's a poem about a quick brown fox, a compiler, a GPU, ` | yes — it frames the prompt; the 64-token cap ends it mid-plan, before "blue" |
| Qwen3-0.6B-Q8_0 | band8300 | `Okay, let's see. The user provided a long text about a fox, compiler, GPU, and tile, and then asked,` | yes, same shape |
| Qwen3-0.6B-Q8_0 | tools | `Okay, the user is asking about the weather in Lisbon. I need to use the get_weather function. The fu` | yes |
| Qwen3-4B-Q4_K_M | band16 | `Okay, let's see. The user provided a text that seems to be a repetition of the same sentence multipl` | yes |
| Qwen3-4B-Q4_K_M | band8300 | `Okay, the user is asking for the color of the sky in one word. Let me think. The previous text is a ` | yes |
| Qwen3-4B-Q4_K_M | tools | `Okay, the user is asking about the weather in Lisbon. I need to use the get_weather function. The fu` | yes |
| Qwen3-4B-Q6_K | band16 | `Okay, let's see. The user provided a text that seems to be a repetition of the same sentence about a` | yes |
| Qwen3-4B-Q6_K | band8300 | `Okay, the user is asking for the color of the sky in one word. Let me think. The provided text is a ` | yes |
| Qwen3-4B-Q6_K | tools | `Okay, the user is asking for the weather in Lisbon. I need to use the get_weather function. Let me c` | yes |
| Qwen3-8B-Q4_K_M | band16 | `Okay, let's see. The user provided a text that repeats the sentence about the quick brown fox and me` | yes |
| Qwen3-8B-Q4_K_M | band8300 | `Okay, let's see. The user provided a long text that repeats the sentence about the quick brown fox a` | yes |
| Qwen3-8B-Q4_K_M | tools | `Okay, the user is asking about the weather in Lisbon. I need to use the get_weather function. Let me` | yes |
| LFM3-1.7B-F16 | band16 | `We need to parse the user's input. The user says: "You are a terse assistant. Read the text and answ` | yes (same meta-plan shape) |
| LFM3-1.7B-F16 | band8300 | `We need to parse the user's input. The user says: "You are a terse assistant. Read the text and answ` | yes |
| LFM3-1.7B-F16 | tools | `We need to get the weather in Lisbon using the `get_weather` tool. The function requires the paramet` | yes |

Caveat on the band cells: every model is a thinking model at temperature 0 and the cell caps
`max_tokens: 64`, so the saved text is the plan, not the one-word answer; the "sky"/colour answer is
cut off by the cap. Topic is right, the deliverable token is never reached. That is the harness's
shape (script, not app), identical in beta.7.

Extra observation, not gated by the script: comparing all cells layer vs tensor, only
`Qwen3-4B-Q6_K` `band8300` differs (`tensor` `"...The main question is straightforward: what color is
the sky?\n\nFrom\n--\n"` against `layer` `"...The actual question is straightforward: what color is
the sky?\n\nThe\n--\n"`, first difference at offset 228). The contract's gated set is band16/300/1100,
which is byte-identical for all five.

## Tools cell

`tool_calls` are not written to any saved file — the script keeps the prose answer only
(`scripts/stress-release.sh:200-204`), and `want_tool=True` fails the cell when
`msg["tool_calls"]` is empty. All fifteen tools cells (5 models x tensor/layer/ngl0 is 3, plus LFM3
ngl0 has no tools cell; tensor and layer only) are `PASS`, so `tool_calls` was non-empty in each;
the function name and the arguments are not in the evidence. The answer text names the function
(`get_weather`) and the argument (`city` / `"Lisbon"`) in prose, e.g. Qwen3-0.6B-Q8_0
`"I should call the function with \"Lisbon\" as the argument."`; that is the model's plan, not the
recorded `tool_calls` payload.

## grep counts over the model's server logs (15 logs)

`kernel not found`, `exited with code`, `GGML_ASSERT`, `TEXT BAD`, `@@@@`: **0 in every log of every
model**. No `failed to create pipeline` either (the script's own check, which would have printed a
`(log) FAIL` row — none exists).

Separately, the logs do carry driver-refusal warnings, handled by fallback, 4-6 per model:

- `the driver refused kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64; using ..._w64_lds32`
- `the driver refused kernel_flash_attn_ext_vec_amd_dk128_kf16_vf16_w64_wg32; using ..._w64_wg32_lds32`
- `the driver refused kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16_w64_lg16; the tile kernel takes the prefill`

These are not `kernel not found`; they are the shipped fallback path.

## What the script could not run

- `parallel2` — SKIP, `--parallel 1` in the app's launch.
- LFM3 tensor and ngl0 `identical-vs-previous` — SKIP: beta.7 never produced those runs
  (`LLAMA_SPLIT_MODE_TENSOR not implemented for architecture 'lfm3'`).
- `drafter` mode — not in this set's mode list.
- The rest of contract §4's set (14B, Nemotron, Ternary-Bonsai, Underdog, Ornith-35B with and
  without its drafter) was not in `STRESS_MODELS`; not run here.

## Verdict

15 of 15 model/mode runs completed with 20 PASS / 1 SKIP (parallel2) on the GPU modes and 3 PASS on
`-ngl 0`; no FAIL, no REFUSED, no crash, no new DiagnosticReport, no `kernel not found` /
`exited with code` / `GGML_ASSERT` / `TEXT BAD` / `@@@@`. The only failing gated rows are
`ngl0 identical-vs-previous` on four models (CPU text against beta.7's CPU text), and two SKIPs
where beta.7 had no LFM3 tensor/ngl0 run at all.