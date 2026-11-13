# Ticket 26 — 35B DFlash drafter band1100 "different first token"

**Verdict: the ticket's premise does not reproduce.** In 11 runs of the shipped beta 8 engine,
band1100 output is not a function of draft-vs-tensor. Tensor mode alone produced all four distinct
band1100 texts seen, including the `"Thinking Process:"` text the ticket attributes to draft mode.
There is no draft-specific defect to fix here; band1100 is nondeterministic in both modes.

All claims below point to a file under `.scratch/beta8-unified-engine/evidence/26/`.

---

## 1. Runs and exit codes

Runner: `scripts/stress-release.sh <bin> <model>` with `MODES`, `CELLS`, `DRAFT_EXTRA`, `APPLOG`
and absolute `OUT`/model paths, one server at a time, from `/Users/sam/firellama`.
Per-run driver output: `$E/<label>.log`; per-run table: `$E/<label>/tables/stress.tsv`.

| label | mode | engine | cells | rc | notes |
|---|---|---|---|---|---|
| d1 | draft | beta.8 | band16 band300 band1100 | 0 | baseline draft |
| d2 | draft | beta.8 | band16 band300 band1100 | 0 | repeat of d1 |
| d3 | draft | beta.8 | band1100 | 0 | repeat |
| t1 | tensor | beta.8 | band16 band300 band1100 | 0 | baseline tensor |
| t2 | tensor | beta.8 | band16 band300 band1100 | 0 | repeat of t1 |
| t3 | tensor | beta.8 | band1100 | 0 | repeat |
| b7d | draft | **beta.7** | band16 band300 band1100 | 0 | previous release's binary |
| moe | draft | beta.8 | band16 band300 band1100 | 0 | `TOSH_OFFLOAD_MOE=1` intended (not applied, see §6) |
| nopo | draft | beta.8 | band16 band300 band1100 | 0 | `DRAFT_EXTRA=--no-op-offload` |
| nopo2 | draft | beta.8 | band1100 | 0 | repeat of nopo |
| ub512 | draft | beta.8 | band16 band300 band1100 | 0 | `-ub 512` intended (did not take effect, see §6) |

Every run finished; **no FAIL rows** in any `stress.tsv` (`grep FAIL */tables/stress.tsv` empty).
27 PASS + 27 SKIP rows total (SKIPs are the `identical-vs-*` rows the single-model runs cannot fill,
and the `drafter-head` row when the target's head is on a card).

## 2. band1100 is nondeterministic in tensor mode — the key result

`compare.txt` and `final-table.txt` hold the full comparison. band1100 by content hash:

| sha | len | produced by |
|---|---|---|
| `79a3dc8c` | 274 | `d1`(draft), `t3`(**tensor**), `nopo`(draft), `ub512`(draft), REF beta8-tensor, REF beta7-draft |
| `985364fb` | 267 | `t2`(**tensor**), `b7d`(draft), `moe`(draft), REF beta8-draft |
| `49266056` | 266 | `d3`(draft), `t1`(**tensor**), `nopo2`(draft) |
| `9830335f` | 269 | `d2`(draft) |

Four distinct outputs across 11 runs. **Tensor runs t1, t2, t3 gave three different texts.**
`t2` — plain `-ngl 99`, no drafter, `--split-mode tensor`, no `-md` — produced
`"Thinking Process:\n\n1.  **Analyze the Request:**"`, the exact text the ticket calls draft-only.

Proof `t2` carried no drafter: `grep -ac "dflash\|spec-type\|draft" t2/*.log` → `0`; plan line has no
drafting context; `t2/tables/stress.tsv` has no `drafter-head` row (only `draft` mode emits that).
`t2/ornith-1.0-35b-Q6_K-tensor.env` = `TOSH_AUTO_KV=auto GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1
GGML_METAL_DEVICE_LIST=0,1` — no `TOSH_MIRROR_OUTPUT_HEAD`, which the runner adds only when `-md` is
present.

So: the first token at band1100 is not decided by drafting. Ticket 26's "draft differs from tensor"
is a sampling artifact of which run you compare.

## 3. What *is* stable

- band16 (83 prompt tokens): **byte-identical in every run** that ran it — d1, d2, t1, t2, b7d, moe,
  nopo, ub512 all `SAME` vs beta8-tensor (290 chars). The defect, if any, needs a long prompt.
- band300: identical for t1, t2, nopo, ub512, b7d; differs at offset 73 for d1, d2, moe.
  d3/t3/nopo2 did not run band300.
- The four texts all agree on the first 40 characters *except* `985364fb`, which diverges at offset 0
  (`'Thinking Process:'` vs `"Here's a thinking process:"`).

## 4. Per-run plan / quota / offload lines

Full text: `plan-lines.txt`. Verdict per run (`ub`, `hot`, `coverage` from the plan line):

| label | mode | ub | hot | cov | dev0 quota | dev1 quota | global | op offload lines |
|---|---|---|---|---|---|---|---|---|
| d1 | draft | 1024 | 4.1 GiB | 1.17 | 31 (free 5534) | 35 (free 5906) | 31 | 3 (on) |
| d2 | draft | 1024 | 4.4 GiB | 1.18 | 36 (free 5814) | 35 | 35 | 3 (on) |
| d3 | draft | 1024 | 4.4 GiB | 1.18 | 38 (free 5915) | 34 (free 5828) | 34 | 3 (on) |
| t1 | tensor | 1024 | 4.6 GiB | 1.19 | — | — | — | 0 |
| t2 | tensor | 1024 | 4.6 GiB | 1.19 | — | — | — | 0 |
| t3 | tensor | 1024 | 4.6 GiB | 1.19 | — | — | — | 0 |
| b7d | draft | 512 | 4.1 GiB | 1.17 | 37 (free 5785) | 37 | 37 | 0 |
| moe | draft | 1024 | 4.0 GiB | 1.16 | 36 (free 5804) | 35 | 35 | 3 (on) |
| nopo | draft | 1024 | 3.9 GiB | 1.16 | 27 (free 5357) | 34 (free 5828) | 27 | 0 |
| nopo2 | draft | 1024 | 4.5 GiB | 1.18 | 39 (free 5948) | 34 | 34 | 0 |
| ub512 | draft | 1024 | 4.4 GiB | 1.18 | 36 (free 5821) | 35 | 35 | 3 (on) |

Every draft run: `mode=PLAN_FULL_HOST_DMOE reason=FULL_HOST_SAFE warnings=COVERAGE_CONSTRAINED
CONSTRAINED ctx=32768 kv=f16`. Tensor runs emit **only** the plan line — no `dmoe_init`, no
`llama_tosh_dmoe_budget`, no `load_tensors`, no `op offload`. That is the tensor path, not missing
evidence.

The dmoe quota lines exist only in draft logs, e.g. d1:

```
dmoe_init: device 0: free 5534 MiB, per_expert 52 MiB -> quota 31
dmoe_init: device 1: free 5906 MiB, per_expert 47 MiB -> quota 35
dmoe_init: multi-device mode: 2 devices, global quota = 31 (min of per-device quotas)
dmoe_init: dynamic residency, 31 slots per layer, decay 0.980, budget 10240 promotions per graph
```

Card 0's free VRAM at budget time swings 5357–5948 MiB run to run (the display shares card 0), so the
global quota swings 27–39. `hot` and `coverage` move with it (3.9–4.5 GiB, 1.16–1.19).

## 5. Determinism: d1 vs d2

Not byte-identical. band16 identical (290); band300 271 vs 263 (diff@73); band1100 274 vs 269
(diff@100). Same command, same binary, same model, minutes apart. With three tensor repeats also
disagreeing (t1=266, t2=267, t3=274), the run-to-run spread is the engine's, not draft mode's.

## 6. Which switch reproduces tensor's band1100 text in draft mode

**None does so reliably, and none needs to.**

- `--no-op-offload` (nopo, nopo2): nopo gave the tensor text, nopo2 did not. Two runs, two answers.
  The flag *does* take effect — nopo/nopo2 logs have zero `sched_reserve: op offload` lines — but it
  does not pin the output.
- `TOSH_OFFLOAD_MOE=1` (moe): **not applied.** The runner's `env "${runenv[@]}"` does not forward
  extra variables, and `moe/ornith-1.0-35b-Q6_K-draft.env` shows no `TOSH_OFFLOAD_MOE`. The switch is
  read at `vendor/llama.cpp/ggml/src/ggml-backend.cpp:1164` (`getenv("TOSH_OFFLOAD_MOE")`), so it must
  be exported into the script's environment to have any effect. `moe`'s output is therefore just
  another draft run — it landed on the `"Thinking Process:"` text like `b7d` and `t2`.
- `-ub 512` (ub512): **did not take effect.** `tosh-plan.cpp:1299` overwrites `params.n_ubatch` with
  the plan's choice; ub512's log says `n_ubatch = 1024` twice and the plan line reads `ub=1024`.
- beta.7 vs beta.8: `b7d` (beta.7 binary, ub=512, quota 37) gave the `"Thinking Process:"` text.
  Beta.7 does not give the good text either.

What the switches *do* show: the plan state (quota, `hot`, `coverage`, op-offload) moves with card 0's
free VRAM, and the text moves with it — but not deterministically, since tensor runs with an identical
plan line (t1/t2/t3 all `vram=10.0GiB hot=4.6GiB cov=1.19 ub=1024`) still produced three texts.

## 7. Likely mechanism (from the source, not proven)

`llama_context.cpp:816-846` sizes the worst-case graph with op offload on, and if the GPU compute
buffer would exceed `TOSH_OFFLOAD_MAX_COMPUTE_MB` (default 1536) it turns offload off and rebuilds the
scheduler. The decision is memory-state dependent, so the executed graph can differ between runs.
`ggml-backend.cpp:2413` further gates expert prefetch on `op_offload && GGML_SCHED_PREFETCH_EXPERTS`,
and `ggml-backend.cpp:1167` gates host-weight op offload. A different executed graph (different
reduction order, different expert residency) at a 1486-token prompt is a plausible source of a
flipped first token. This is inference from the code paths; it is not isolated by these runs.

## 8. What was skipped and why

- No re-run of `moe` with `TOSH_OFFLOAD_MOE` exported. The variable cannot reach the server through
  the runner as invoked, and since no switch pins the output (§6) the re-run could not have settled
  the question. Left as "not applied" rather than reported as a result.
- `ub512` reported as the plan's `ub=1024`, not as a 512-ubatch experiment: the plan overrides the
  flag, so the run is a duplicate of `d2`-class conditions, not a ubatch test.
- No source edits, no builds, no commits, no installs. Only `stress-release.sh` was invoked, with
  `APPLOG`, absolute `OUT`, absolute model path, `MODES`, `CELLS`, `DRAFT_EXTRA`.
- `127.0.0.1:8080`, the user's running app, and the default domains were never touched.
- No full process environment was saved (`ps eww`/`env` never run).

## 9. Crash safety

`ls /Library/Logs/DiagnosticReports/ | sort` before the first run
(`diagreports-before-run1.txt`, 39 names) and after every run
(`diagreports-after-run1.txt` … `after-run12.txt`, all 39 names). `comm -13 before after` was empty for
every comparison: **no new panic, watchdog or gpuRestart report.** No run crashed the Mac.

## 10. Files

- `final-table.txt` — the compare table (§2, §3)
- `compare.txt`, `compare.py` — exact-equality compare incl. the three gate references
- `plan-lines.txt` — per-run plan / quota / op-offload lines (§4)
- `checks.txt`, `checks.py` — determinism and per-cell checks
- `texts/` — extracted band1100 texts, `index.txt`, `d1-vs-d2.diff`
- `<label>/` — per-run server log, `.env`, `.cells.tsv`, `tables/stress.tsv`, answers JSON/TXT
- `<label>.log` — driver stdout for each run
- `diagreports-*.txt` — panic-name comparison evidence