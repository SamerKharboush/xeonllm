# 25: -ngl 0 CPU text differs from beta.7 - diagnosis (2026-11-13)

Worktree: /Users/sam/Library/Caches/xeonllm-wt-fa (series 0001-0086, pin d81235049), build dir build-fa.
Everything below points at a file in this directory. Machine state before/after: `diagreports-before.txt`,
`diagreports-after.txt`, `ps-before.txt`, `ps-after.txt`.

## 1. Engines and builds (sha256, first 16 hex)

| engine | path | sha prefix |
|---|---|---|
| beta.7 engine | evidence/gates-beta8/beta7-bin/llama-server | 1a68d3efcbf476e7 |
| beta 8 engine | dist/XeonLLM.app/Contents/Resources/bin/llama-server | 63eb2a01af361672 |
| worktree HEAD (0001-0086) | build-fa/bin/llama-server | 53546683d2539c54 |
| HEAD minus 0082+0086 | build-fa/bin/llama-server | f01bb3615432c450 |
| HEAD minus 0085 | build-fa/bin/llama-server | 7f704be525ede661 |
| HEAD minus 0082,0086,0083,0085 | build-fa/bin/llama-server | 3310558b062c5fa5 |
| HEAD with the 0083 hunk reverted only | build-fa/bin/llama-server | 5e3b3f6335f2b738 |
| HEAD rebuilt after restoring | build-fa/bin/llama-server | 53546683d2539c54 |

`static-initial.txt` records both CMake configs (build-fa vs vendor/llama.cpp/build-static: same ISA flags
`-msse4.2 -mf16c -mavx`, GGML_NATIVE=OFF, GGML_OPENMP=ON). The worktree rebuild is byte-identical to the
build-fa binary before the experiments (same sha), so a worktree build is a valid engine for this comparison.

## 2. Result table (Qwen3-0.6B-Q8_0, ngl0, `-ub 128 -b 128 -t 12`, 12 threads, prompt_tokens=1483)

| label | engine / patch state | vs beta.7 ref | vs beta 8 ref |
|---|---|---|---|
| b7-1 | beta.7 engine, band1100 only (cold server) | IDENT (268 chars) | diff @216 |
| h-nonative | beta.7 engine, repeat of b7-1 | IDENT (268) | diff @216 |
| b73 | beta.7 engine, cells 16/300/1100 | all three IDENT | band1100 diff @216 |
| b8-1 | beta 8 engine, band1100 only | diff @47 (271) | diff @47 (271) |
| b8-2 | beta 8 engine, repeat of b8-1 | diff @47 (271) | diff @47 (271) |
| d-all3 | beta 8 engine, cells 16/300/1100 | band16/band300 IDENT, band1100 diff @216 | all three IDENT |
| h | worktree HEAD, band1100 only | diff @47 (271) | diff @47 (271) |
| h-nonative | (beta.7 engine, see above) | | |
| h-nopo | worktree HEAD, band1100 only, `--no-op-offload` | diff @47 (271) | diff @47 (271) |
| h3 | worktree HEAD, cells 16/300/1100 | band16/band300 IDENT, band1100 diff @216 | all three IDENT |
| h3-nopo | worktree HEAD, same cells, `--no-op-offload` | band16/band300 IDENT, band1100 diff @216 | all three IDENT |
| no82 | HEAD minus core/0082 and core/0086 | band16/band300 IDENT, band1100 diff @216 | all three IDENT |
| no8385 | HEAD minus 0082,0086,0083,0085 | all three IDENT | band16/band300 IDENT, band1100 diff @216 |
| no83 | same build as no8385 (sha 3310558b062c5fa5) | all three IDENT | band1100 diff @216 |
| no85 | HEAD minus 0085 (0083 present) | band16/band300 IDENT, band1100 diff @216 | all three IDENT |
| hunk | HEAD, only the 0083 hunk reverted | all three IDENT | band16/band300 IDENT, band1100 diff @216 |
| w64 | HEAD, `TOSH_FA_PF_W64=1` (0083 escape hatch) | all three IDENT | band16/band300 IDENT, band1100 diff @216 |

Qwen3-8B-Q4_K_M, ngl0 band16 (`hunk-8b`, 0083 hunk reverted): beta.7 ref IDENT (282 chars),
beta 8 ref diff @225 (282 vs 282).

Full per-label diffs: `summary.json`. Per-label answer files: `<label>/<stem>-ngl0.answers.json`,
server logs `<label>/<stem>-ngl0.server.log`, cell tables `<label>/tables/stress.tsv`.

## 3. Determinism / environment (step 1)

- beta.7 engine reproduces the beta.7 reference exactly, twice (`b7-1`, `h-nonative`; and `b73` on all three cells).
- beta 8 engine reproduces the gates-beta8 reference exactly when the three ngl0 cells run in the same
  order as in the gate run (`d-all3`: band16/band300/band1100, `TOSH_FA_AMD=1`, `-ngl 0`), and the worktree
  HEAD build matches it byte for byte (`h3`).
- So the text is deterministic per (engine, cell sequence); no bisect stop needed.
- Side observation (not the ticket): a band1100 request sent as the *first* request of a fresh server gives
  271 chars on both engines (`b8-1`, `h`); the same request after band16+band300 gives 262 (beta 8) or 268 (beta.7).
  The gate references were produced with all three cells, so comparisons here use the same sequence.

## 4. Bisect

| build | patch state | text |
|---|---|---|
| HEAD 0001-0086 | all | beta 8 |
| no82 (0082+0086 reverted) | 0082,0086 off | beta 8 -> 0082/0086 ruled out |
| no85 (0085 reverted, 0083 present) | 0085 off | beta 8 -> 0085 ruled out |
| no8385 (0082,0086,0083,0085 off) | 0083+0085 off | beta.7 |
| hunk (0083 hunk reverted, everything else at HEAD) | only that hunk off | beta.7 |
| w64 (HEAD, `TOSH_FA_PF_W64=1`) | hunk neutralised by its own env knob | beta.7 |

0082 and 0086 had to be reverted before 0082 could be reverse-applied (0086 edits the same hunk of
`ggml/src/ggml-backend.cpp`, line 1158): `git apply -R core/0086` first, then `core/0082`.
0083 and 0085 both edit `src/llama-graph.cpp` in the same region, so the two patches cannot be reverse-applied
independently with the stock patch files; `no83` therefore ran the both-off build (`no8385`), and the
single-patch states were produced by reverting 0085 only (`no85`) and by the hand edit below.

`--no-op-offload` (the op-offload path added by 0082) does not change anything (`h-nopo` == `h`,
`h3-nopo` == `h3`), so the prompt offload itself is not involved.

## 5. Culprit (step 3)

`patches/llama/metal/0083-metal-fa-prefill-block-is-off-on-64-lane-cards.patch`, single hunk in
`src/llama-graph.cpp`, `llm_graph_context::build_attn_mha()`, the `amd_prefill_fa_blocked` condition
(worktree file, HEAD): `src/llama-graph.cpp:2955` (condition), lines 2956-2960:

    const bool amd_prefill_fa_blocked =
        (q->ne[0] == 64 || q->ne[0] == 128) &&
        metal_simd_width != nullptr &&
        (strcmp(metal_simd_width, "32") == 0 ||
         (strcmp(metal_simd_width, "64") == 0 && getenv("TOSH_FA_PF_W64") != nullptr)) &&
        hparams.f_max_alibi_bias == 0.0f && !hparams.attn_soft_cap &&
        getenv("TOSH_FA_PF_DISABLE") == nullptr;

beta.7 had `... (strcmp(metal_simd_width, "32") == 0 || strcmp(metal_simd_width, "64") == 0) ...`.
The flag gates `amd_prefill_decomposed` (`src/llama-graph.cpp:2983`, used at 2993) and through it
`use_flash_attn` (`src/llama-graph.cpp:2997`). So for a prefill batch longer than
`decomposed_min_tokens` (`src/llama-graph.cpp:2963`, 32 for head 64/128) the graph is one of two shapes:

- 0083 off (beta.7): decomposed prefill - `GGML_OP_MUL_MAT` for KQ, soft_max, `GGML_OP_MUL_MAT` for AV.
- 0083 on (beta 8): `ggml_flash_attn_ext`.

`metal_simd_width` is the probed SIMD width of the Metal device and is non-null whenever a D700 is
registered, which is also true at `-ngl 0` (all layers in RAM, all weights on the host). The decision is
therefore taken on the CPU-only run too, and the two routes sum the same attention in a different order.

Proof that this hunk alone is the cause: `hunk` (HEAD with only this condition put back to the beta.7
form) returns beta.7's text on all three cells, and `hunk-8b` returns beta.7's 8B band16 text (282 chars)
while beta 8's is different at offset 225. Independent confirmation at HEAD with no code change:
`TOSH_FA_PF_W64=1` (`w64`) restores beta.7's text on all three cells.

## 6. Correctness bug or reordering?

Not a correctness bug. Both routes evaluate the same attention; `ggml_flash_attn_ext` on the CPU keeps an
online (running) softmax accumulator, the decomposed route materialises the full f32 KQ and applies
soft_max before the AV mat-vec, so the floating-point sums are associated differently. The divergence
shows up only after 216 characters of greedy text on a 1483-token prompt, and only where the two paths
differ in rounding. It is a legitimate reordering - but it is a *backend-visible graph change* driven by a
GPU measurement, taken from the Metal device's SIMD width rather than from where the node will actually run.

Ruled out: core/0082 (prompt offload + compute-buffer cap in `sched_reserve`), core/0086 (MoE host-weight
offload), metal/0085 (decomposed-KQ size cap), and metal/0084 (Metal-only files: `ggml-metal-device.h`,
`ggml-metal-ops.cpp`, `ggml-metal.cpp`; not exercised here, and reverting 0083 alone already restores
beta.7's text with 0084 still applied).

## 7. Machine safety

`diagreports-before.txt` and `diagreports-after.txt` are identical in the top three entries
(`XeonLLM_2026-11-12-230458...diag`, `XeonLLM_2026-11-12-200559...cpu_resource.diag`,
`XeonLLM_2026-11-12-193807...diag`): no new panic/watchdog/gpuRestart report. `ps-before.txt` and
`ps-after.txt` each list only pid 747 (`/Users/sam/llama.cpp/build-metal/bin/llama-server`), which was
never touched; one engine at a time, all builds with `-j8`, `-ngl 0` only.