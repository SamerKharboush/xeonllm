# R3-C — contract section 4, 35B (group C), beta 8

Run: `STRESS_MODELS="ornith-1.0-35b-Q6_K" bash .scratch/beta8-unified-engine/evidence/gates-beta8/stress-set.sh`,
log `.scratch/beta8-unified-engine/evidence/gates-beta8/stress-C.log`. Start 16:38, script end 17:00
(`stat`: stress-C.log Nov 13 17:00:25, last line `### done`). No source or script changed.

## Launch (from `out/set/ornith-1.0-35b-Q6_K.applog`, the test profile `dev.xeonllm.gatetest`)

```
== ornith-1.0-35b-Q6_K
 placement: expert tier (MoE, does not fit in VRAM: one card holds attention and the hot experts, the CPU computes the rest)
 args: -m /Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/models35/ornith-1.0-35b-Q6_K.gguf -ngl 99 -c 32768 -t 12 -fa 1 --host 127.0.0.1 --port 18099 --dynamic-moe on --load-mode none --jinja --n
launch flags from: /Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/out/set/ornith-1.0-35b-Q6_K.applog
```

No `context:` line: the app logs `settings: ngl=99 memory=auto-plan (auto, kv auto) ctx=32768 fa=auto ctk=f16 ctv=f16 cacheRAM=2048`
and `[XeonLLM] memory plan: Dynamic MoE · ~1.2 GiB expert cache · 32K context · KV F16 · ~0.8 GiB VRAM headroom | Dynamic MoE: the model does not fit in VRAM; the GPU keeps the most used experts.`
The launch header also carries `dflash : off by memory planner (need 30.99 GiB, budget 10.5 GiB)`.

## Cells (script lines, `stress-C.log`)

```
-- ornith-1.0-35b-Q6_K-draft.cells.tsv:   20 PASS    1 SKIP
-- ornith-1.0-35b-Q6_K-tensor.cells.tsv:   20 PASS    1 SKIP
```

No non-PASS cells other than the SKIP, whose reason column is:

```
ornith-1.0-35b-Q6_K.gguf	draft	drafter-head	SKIP	the target's head is on a card; no copy is made	0
ornith-1.0-35b-Q6_K.gguf	tensor	identical-vs-ngl0	SKIP	no ngl0 run of this model	0
ornith-1.0-35b-Q6_K.gguf	draft	identical-vs-ngl0	SKIP	no ngl0 run of this model	0
```

`parallel2` is the 1 SKIP per mode: `parallel2	SKIP	--parallel 1 does not allow it	0`.

MODES was `tensor draft`; `layer` and `ngl0` were not run (the script's case line for this model is
`run $L/ornith-1.0-35b-Q6_K.gguf "tensor draft"`).

## Identical / drafter lines (`out/set/ornith-1.0-35b-Q6_K/tables/stress.tsv`)

```
ornith-1.0-35b-Q6_K.gguf	tensor	identical-vs-previous	PASS	band16 band300 band1100 byte-identical	0
ornith-1.0-35b-Q6_K.gguf	draft	identical-vs-tensor	FAIL	band1100 differs at offset 0	0
ornith-1.0-35b-Q6_K.gguf	draft	identical-vs-previous	FAIL	band1100 differs at offset 0	0
```

layer-vs-tensor: not run (no `layer` mode). GPU vs `-ngl 0`: not run (no `ngl0` mode), reported only anyway.

## Answers (first 100 chars, `out/set/ornith-1.0-35b-Q6_K/*.answers.json`)

tensor:
- band4200 `Thinking Process:\n\n1.  **Analyze the Request:**\n    *   Input text: A very long, repetitive string o` — on topic (restates prompt/question; ends at the question, no final word).
- band8300 `Here's a thinking process:\n\n1.  **Analyze User Input:**\n   - **Text:** A massively repetitive paragr` — on topic in shape, cut before the answer.
- tools `The user is asking for the weather in Lisbon and explicitly requested to use the tool.\nI need to cal` — on topic.

draft:
- band4200 `Here's a thinking process:\n\n1.  **Analyze User Input:**\n   - **Text:** A massively repetitive paragr`
- band8300 `Here's a thinking process:\n\n1.  **Analyze User Input:**\n   - **Text:** A massively repetitive paragr`
- tools `The user is asking for the weather in Lisbon and explicitly requested to use the tool.\nI need to cal`

Both modes stop mid-plan: `completion_tokens=64` on every band (cells.tsv), so no band ever reaches the
one-word answer. Text is on topic; the answers are truncated by `max_tokens 64`, not empty or `@@@@`.

## Tools cell (ticket 20)

```
ornith-1.0-35b-Q6_K-tensor.cells.tsv: tools PASS
ornith-1.0-35b-Q6_K-draft.cells.tsv: tools PASS
```
cells.tsv note: `tools	PASS	prompt_tokens=277 completion_tokens=81 13.0s	277` (tensor). PASS requires
`tool_calls` (driver: `if want_tool and not calls: add(name,"FAIL","no tool_calls in the answer")`).
The name/arguments are not written to any saved file (the driver stores only reasoning+content), so I
cannot quote them; the saved answer text is `` `get_weather` `` with `"city"` = `"Lisbon"`, no JSON
braces. The tool call was not lost in either mode — the beta.7 loss did not reproduce.

## Draft acceptance (`ornith-1.0-35b-Q6_K-draft.server.log`, 18 lines)

```
0.48.248.501 I slot print_timing: id  0 | task 0 | draft acceptance = 0.82500 (   33 accepted /    40 generated), mean len =  3.36
10.33.215.575 I slot print_timing: id  0 | task 808 | draft acceptance = 0.78788 (   26 accepted /    33 generated), mean len =  3.36
```
head placement: `0.36.300.118 I llama_context: dflash lm head copied from MTL1_Private to MTL0_Private (397.9 MiB, q6_K)`
(the script's drafter-head cell still reads SKIP because it looks for the `dflash lm head copied to`
wording; the line above is what the log holds).

## Grep counts (both server logs)

| pattern | tensor | draft |
|---|---|---|
| `kernel not found` | 0 | 0 |
| `exited with code` | 0 | 0 |
| `GGML_ASSERT` | 0 | 0 |
| `TEXT BAD` | 0 | 0 |
| `@@@@` | 0 | 0 |

## Safety

`/Library/Logs/DiagnosticReports/` newest three, before (16:38) and after (17:00), identical names:
`XeonLLM_2026-11-12-230458_Sams-Mac-Pro.diag`, `XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag`,
`XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag`. No new panic/watchdog/gpuRestart file.

Nothing failed to run. The prompt-offload control (addendum) was not run: the script made no `ngl0`
run, so there is no beta 8 `-ngl 0` text to compare with beta.7.