# Engine survey, 2026-11-04: what other engines do, and what can run on a D700 pair with an AVX1 Xeon

This builds on `engine-survey-2026-11-02.md`, `strata-policy-not-code-2026-10-20.md`,
`third-party-receipts-2026-10-21.md`, `uzu-and-magnitude-on-this-mac-2026-10-29.md` and the
pooled-budget map (`.scratch/pooled-budget/map.md`). Nothing below was built, run or benchmarked
for this survey. Every "measured" number comes from an earlier evidence file in this repo, which
is named next to it, and was taken on this machine: a Mac Pro 6,1 with a Xeon E5-2697 v2 (AVX and
F16C, no AVX2 or FMA), 64 GB DDR3, 2x FirePro D700 (GCN 1.0, Metal only, not bridged) and
macOS 15.8. Throughput figures from other projects are quoted together with the hardware they
were measured on. None of them is offered as an expected result here.

**Sources.** Each source was read at a fixed commit, from a shallow or blobless clone made on
2026-11-04 in the session scratchpad. Nothing was added to the repo.

| repo | commit |
|---|---|
| ggml-org/llama.cpp (upstream HEAD) | `cd959bae99ff4bed22bef2604f45241c09bbb8c8` (681 commits after the pin `d81235049`, 2026-10-05) |
| ikawrakow/ik_llama.cpp | `7cfc9ed1affd7bede184b64effe261fb06da7bf0` |
| kvcache-ai/ktransformers | `c9873312643b615a717832946fba0346e69ab035` |
| SJTU-IPADS/PowerInfer | `8bd56d69906c9d2dba4d3bf6899763401e01a9a4` |
| Mozilla-Ocho/llamafile | `6bfbec3af98c278c399acc21403c0ed8eaa23bef` |
| microsoft/T-MAC | `7042f8f73330bd083bc1e4bc5ccb3f88a4904aee` |
| microsoft/BitNet | `0b341e582afbf9e1011f24744b554c96a3477eb5` |

Papers were read on arXiv (abstract pages). Official documentation pages were fetched for vLLM,
MLX, MLC-LLM and ExLlamaV3. The shipped `dist/XeonLLM.app/.../llama-server` was disassembled
with `otool` (read-only) to confirm which ISA variant ships: it contains `ymm` instructions (9253)
and `vcvtph2ps` (188), and no FMA mnemonics. So the release engine is the `TOSH_AVX1=1` variant
(AVX+F16C, `scripts/build-engines.sh:176-179`), not the SSE4.2 baseline. The pin's AVX1 code
paths below are therefore live in the shipped binary.

## 1. The answer

On this box every token is limited by how fast weights can be read. The measured read ceilings
are of the same order on all three devices:
- the Xeon's read-only sum: 51.6 GB/s (`the-xeon-memory-bandwidth-2026-10-25.md`);
- the D700's shipped Q6_K/Q4_K decode mat-vec: 37-43 GB/s at large shapes, and 50-66 GB/s with
  the `nr0=8` variants (`the-dense-mat-vec-gate-and-nr0-2026-10-30.md`).

Upstream has added no AVX1 CPU work since the pin (§3.9). Every external engine with a faster CPU
path requires AVX2 or better (§4).

So the gains are not in importing an engine. They are in four places:

1. **Use the card that sits idle.** On the 35B expert tier the second card does nothing. The app
   keeps the DFlash drafter off there because its planner counts all 26.6 GiB of experts as VRAM
   (§3.4).
2. **Make the GCN mat-vec read closer to what the card can deliver.** It is the largest single
   share of a card-resident token: 39.6 ms of a 78 ms 35B token (§3.1). What the card can deliver
   has not been measured yet (ticket 19).
3. **Give the AVX1 CPU the multi-row expert dots it is missing.** The fork's `core/0022` compiles
   them only under `__AVX2__`, so they are inert on this Xeon (§3.3). Speculative verification and
   prefill on the host depend on them.
4. **Prefill host-placed dense models on a card.** The 27B Q8_0 prefills on the host at
   5.0 tok/s (§3.6).

"Bigger" is only fast for MoE models. A dense model read from host RAM is bounded by 51.6 GB/s
divided by its bytes per token, so a 40 GB dense model can never pass about 1.3 tok/s on this
host. A MoE model is bounded by its active bytes, and 64 GB holds a much larger one. Suggested
order: the drafter fix, the mat-vec work (measure first), the AVX1 dots, GPU prefill for host
models, then the LFM3 backport and the open bugs (68, 72).

## 2. Table

"Fork" means `patches/llama/`. "Pin" means upstream `d81235049`, which the fork patches.

| technique | source | runs here? | already in upstream or fork? | expected effect here | effort / risk |
|---|---|---|---|---|---|
| Drafter (DFlash/MTP) on the card the target does not use | fork `spec/0073`; this repo's 10-31 evidence | **yes**: measured with a host target and the drafter on card 1 | engine: yes (pin `COMMON_SPECULATIVE_TYPE_DRAFT_DFLASH`, `common/common.h:179`). The app blocks it: `Sources/Servers/Server.swift:432`, `Sources/Hardware/Hardware.swift:247-253` | the 35B on the expert tier gets a drafter on the idle card. Size unknown until measured | low effort, app-only; display-card slow mode (ticket 72) is a risk |
| GCN mat-vec weight layout repacked at load (Metal analogue of `-rtr` / `CPU_REPACK`) | ik_llama `-rtr` (`common/common.cpp:2490`); upstream CPU repack (`ggml-cpu/repack.cpp:4975`) | **yes** in principle: plain Metal buffers and kernels | no. The fork already has aligned word reads (`metal/0003`, `0060`) and row-count tuning (`0071/0072/0074`) | the largest share of every card-resident token. Unknown until ticket 19 gives the card's own read ceiling | high: every kernel that reads the type must agree on the layout |
| AVX1 multi-row CPU dots (one weight block unpacked for k activation rows) | ik_llama `iqk_mul_mat` (AVX2-only); fork `core/0022` | **yes** if rewritten with 128-bit integer ops | fork has it, **AVX2-only**: `core/0022` patch lines 1454-1477 return NULL without `__AVX2__` | k=1 decode: none. Verify batches, multi-token prefill and parallel slots on the host: unknown until measured | medium: Q6_K/Q4_K/Q8_0 first; bit-exact against `vec_dot` |
| Op offload: host-resident weights computed on a card for big batches | upstream ggml scheduler; pin Metal `offload_op` (`ggml-metal.cpp:850-863`) | **yes** | pin has it. The app hides the cards for host placement (`Server.swift:237`, `:798-818`) | prefill of host-placed dense models (27B Q8_0 host prefill 5.0 tok/s). Bus-bound per ubatch; unknown until measured | low to measure; the PCIe rate is unmeasured |
| Upstream GPU MoE cache (`--moe-cache-mib`) | upstream #29887, #30112, #30637 | partial: backend-agnostic, but refuses tensor split | upstream only, after the pin. The fork's Dynamic MoE (`moe/0020-0068`) covers the same ground with a different policy | none for decode: misses are uploaded and computed on the GPU. The fork computes them on the CPU, which suits this bus (§3.5) | not recommended for decode |
| `MUL_MAT_ID` index −1 skips an expert | upstream #26631 (`701fd25b3`) | **yes** (ggml/Metal) | upstream only, after the pin | lets a card graph skip experts that are not resident without a host join. Unknown | low to backport; check the fork's Dynamic MoE does not already do this |
| n-gram / prompt-lookup self-speculation | pin `COMMON_SPECULATIVE_TYPE_NGRAM_*` (`common/common.h:181-185`); `examples/lookup`, `examples/lookahead` | **yes** | pin | needs no draft model or card. Pays only where the verify batch costs about one token (§3.2) | low; workload-dependent |
| EAGLE-3 | arXiv 2503.01840; pin `DRAFT_EAGLE3` (`common/common.h:177`) | **yes** (engine) if a head exists for the target | pin | the draft is a single layer, cheaper than a 0.6B model. Same verify-cost caveat | needs a trained head per model (UNVERIFIED that one exists for the models on disk) |
| MTP heads | pin `DRAFT_MTP`; fork `spec/0028`, `spec/0040`, `moe/0064` | **yes** | pin + fork | already planned. The plan drops the head when the arena is crowded (`moe/0064`) | — |
| KV quantisation (q8_0, q4_0, turbo2/3/4) | pin `common/arg.cpp:321-334`; fork `quant/0013` | **yes** | pin + fork | more context per card, not more speed: FA is 1.16 ms of a 78 ms 35B token at c=4096 | none new |
| Learned sparse attention (lightning indexer) | fork `metal/0010` | yes, for models with an indexer | fork | model-specific | — |
| Pipeline parallel across 2 cards + CPU, one process | pin `src/llama-context.cpp:535-560` | partial | pin | none at batch-1 decode: layer split is sequential. Only prefill ubatches overlap, and the pin turns it off with tensor overrides or partial offload (`:536-538`) | — |
| Tensor split of the dense part, with experts in Dynamic MoE | fork `mgpu/0015-0018` (tensor split, host allreduce); upstream MoE cache refuses it (`llama-moe-cache.cpp:268-270`) | unknown: never combined | no | halves the per-card share of the 35B's 39.6 ms dense mat-vec, minus 2 host allreduces per layer. Unknown | high; blocked behind the GDN fusion issue that `moe/0053` hit |
| LFM3 architecture | upstream #31252 (`19cce6919`), needs #30874 (`84e66d032`) | yes | upstream only | the model loads (beta.6 "Not covered") | medium backport |
| llamafile tinyBLAS AVX path | llamafile `sgemm.cpp:109-113`; pin `ggml-cpu/llamafile/sgemm.cpp` | **yes** | pin has the AVX path for F32, F16(+F16C), Q8_0, Q4_0, Q5_0 and IQ4_NL; no K-quants | already active for those types | — |
| llamafile `mixmul` (tinyBLAS `MUL_MAT_ID`) AVX path | llamafile `tinyblas_cpu_mixmul_amd_avx.cpp`, `tinyblas_cpu_mixmul.inc:150-270` | yes | not in the pin's ggml | Q4_0/Q8_0/F16 experts only; nothing for Q6_K/Q4_K | medium; narrow |
| ik_llama.cpp IQK kernels, fused MoE, `-rtr`, MLA | ik_llama | **no**: `ggml/src/iqk/iqk_config.h:13` defines `IQK_IMPLEMENT` only under `__AVX2__` or ARM dotprod | ideas partly in the fork (fused gate/up `metal/0051`, `0062`; MoE router fusion `metal/0058`) | — | — |
| KTransformers | kt-kernel | **no**: lowest CPU variant AVX2 (`docker/README-packaging.md:274`); GPU side CUDA/ROCm/XPU | — | — | — |
| PowerInfer / PowerInfer-2 | arXiv 2312.12456, 2406.06282 | **no**: AVX2 x86 (`README.md:81-82`), CUDA/ROCm; Metal is a TODO (`README.md:87`, `:296`); needs ReLU-sparsified models with predictors | — | — | — |
| T-MAC | arXiv 2407.00088 | **no**: kernels are NEON or AVX2 (`python/t_mac/intrins/tbl.cc:4-6`); x86 targets `-mcpu=core-avx2` (`python/t_mac/platform.py:113,125`) | — | — | — |
| BitNet.cpp I2_S / TL2 | microsoft/BitNet | **no**: `ggml_vec_dot_i2_i8_s_1x1` is `#if defined(__AVX2__)` (`src/ggml-bitnet-mad.cpp:199`); TL2 kernels `#ifdef __AVX2__` | ternary already in the fork (`quant/0014`, PQ2/PTQ1 types) | — | — |
| MLX | ml-explore docs | **no**: Apple silicon only | — | — | — |
| vLLM | docs.vllm.ai CPU install | **no**: x86 CPU wants `avx512f`, `avx2` is "limited"; macOS is Apple Silicon only | — | — | — |
| ExLlamaV2/V3 | turboderp-org/exllamav3 README | **no**: CUDA >= 12.4 | — | — | — |
| SGLang, TensorRT-LLM | — | **no**: CUDA/ROCm and NVIDIA-only stacks (not re-fetched; SGLang verdict from pooled-budget ticket 04) | — | — | — |
| MLC-LLM / TVM Metal | llm.mlc.ai docs | UNVERIFIED: the docs name `osx-64` and say Metal is mandatory on Apple targets, but nothing confirms Metal on a non-Apple GPU. Single device; would not read GGUF | — | no mechanism here that our own Metal kernels lack | not pursued |
| FlexGen | arXiv 2303.06865 | **no** (PyTorch/CUDA). The idea is portable | the LP placement idea ≈ `--fit` + `common/tosh-plan.cpp` | throughput-oriented (effective batch 144); does not help batch-1 chat | — |
| LLM in a flash | arXiv 2312.11514 | the idea is portable; no code used | ≈ hot-expert arena (`moe/0020`, `0067`) plus mmap paging | only matters for models over 64 GB | — |
| AirLLM, Strata, uzu, magnitude | earlier receipts | **no** | — | — | — |

## 3. Viable techniques

### 3.1 The GCN dense mat-vec (the largest share of a card-resident token)

**What the receipts show.** On the 35B expert tier, 311 `MUL_MAT/q6_K` ops take 39.553 ms of a
77.957 ms decode graph and read 1.573 GB, an effective 39.8 GB/s
(`which-gpu-ops-a-35b-decode-token-spends-2026-10-25.md`). That was 54 patches ago. Since then
`metal/0071`, `0072` and `0074` moved the row thresholds, after a sweep that measured `r8_w64` at
53.12 GB/s against 42.85 for the shipped `r4_w64` on the 2048 x 248320 head
(`the-dense-mat-vec-gate-and-nr0-2026-10-30.md`, card 1, N=5 processes, sd <= 0.13 GB/s on large
shapes). So the 39.6 ms row is stale and has to be re-measured on beta.6 before anything is
ranked.

**What has not been measured** is how much the card can actually read. Ticket 19 (a read-only
streaming kernel on the D700) is still `ready-for-agent`. The 264 GB/s in
`docs/bench-baseline-2026-09-30.md` is a vendor figure, and CLAUDE.md rule 1 forbids using it as a
denominator. Without ticket 19 nobody can say whether the gap is in the kernel or in the card.

**The idea to import** is runtime repacking: ik_llama's `-rtr` (`common/common.cpp:2490`) and
upstream's `CPU_REPACK` (`ggml-cpu/repack.cpp:4965-5010`, AVX2/NEON/SVE only on the CPU side).
Both rewrite weights once at load into a layout that the hot kernel reads with full-width
contiguous loads. A Metal port would give Q6_K/Q4_K a GCN-specific layout: scales split from
quants, 16-byte-aligned and row-interleaved so that one wave64 reads contiguous segments. It
would sit behind a separate buffer type, so `get_rows`, `mul_mm` and `mul_mm_id` can refuse it
explicitly.
- Expected effect: unknown until ticket 19 says whether the card or the kernel is the limit.
- Risk: high. A second layout touches every kernel that reads the type. The 35B's Q6_K output
  head (397.9 MiB) is also borrowed by the DFlash drafter (`spec/0073`).

**Before writing any kernel, a cheaper measurement:** sweep the existing types (q4_0, q8_0,
iq4_nl, q4_K, q5_K, q6_K) at the same shapes with `test-backend-ops perf -o MUL_MAT`. If the
simple block formats already read much faster than the K-quants on GCN, the layout is the lever.
If they do not, the kernel is.

### 3.2 Speculative decoding: what is in the engine, and why it has lost here

The pin already has draft-simple, EAGLE-3, MTP, DFlash, DSpark and four n-gram variants
(`vendor/llama.cpp/common/common.h:175-185`), plus `examples/lookup` and `examples/lookahead`.
Medusa (arXiv 2401.10774) is not in the pin, and nothing on disk has Medusa heads. EAGLE-3
(arXiv 2503.01840) replaces EAGLE's feature regression with direct token prediction and
multi-layer feature fusion. Its abstract reports up to 6.5x; the hardware behind that figure was
not verified from the abstract (UNVERIFIED).

What this machine has shown:
- A 0.6B draft on the same card as an 8B target: 2.36 against 8.19 tok/s (ticket 60).
- The same draft on the other card: 2.63 against 8.32 tok/s (ticket 62).
- A Qwythos-9B draft for the dense 27B on the host: 1.33 against 1.94 tok/s at 64% acceptance.
  "Each round costs about four host tokens" (pooled-budget ticket 08).
- DFlash for the 35B on the host, drafter on card 1: 12.53 and 11.76 tok/s (head copy on and
  off), and plain decode of 10.93-11.09 tok/s in the same session but a different configuration
  (`the-drafter-head-on-the-card-2026-10-31.md`). The text was byte-identical.

**The mechanism.** Speculation pays only when verifying k tokens costs much less than k single
tokens. On this host, dense decode at k=1 already reads close to the RAM read ceiling: 27B Q8_0
at 1.60 tok/s and 27B Q6_K at 2.03 tok/s both sit below 51.6 GB/s divided by their file sizes. The
27B trial shows verification scaling about linearly with k. Nobody has measured the verify cost
curve t(k)/t(1) for each placement, and that curve decides every speculative method at once.

There are two portable fixes:
- Make host verification cheaper with AVX1 multi-row dots (§3.3).
- Put the drafter on whichever card the target does not use (§3.4).

N-gram self-speculation costs nothing to try, but it inherits the same verify cost.

### 3.3 AVX1 multi-row CPU dots (the fork's own patch is inert on this CPU)

ik_llama's CPU speed comes from GEMM kernels that unpack a weight block once and apply it to
several activation rows (`ggml/src/iqk/iqk_gemm_kquants.cpp` and related files). The fork carries
the same idea in `core/0022-cpu-expert-dots.patch`, as `ggml_cpu_get_vec_dot_multi`, for 1-4
activation rows per weight row. But every x86 implementation and the getter sit inside
`#if defined(__AVX2__)` (patch lines 1454-1477, ending `return NULL;`). On this Xeon the getter
returns NULL, so the multi-row path never runs.

**The portable form** is 128-bit integer code. AVX1 has no 256-bit integer ops, so it would use
SSSE3/SSE4.1 `pmaddubsw`/`pmaddwd` with AVX only for float accumulation. That is the same split
the pin's own AVX1 `vec_dot` paths use (`ggml-cpu/arch/x86/quants.c`, `#elif defined __AVX__`
branches at :2367 q4_K, :2755 q6_K, :1343 q8_0).

**Expected effect:**
- None at k=1 decode, which is bandwidth-bound.
- For k>1 (verify batches, prompt tails, the expert jobs of a prefill ubatch, two parallel
  slots), the unpack work is shared across rows. The size is unknown until the t(k) curve is
  measured.

The CPU experts' share of a Dynamic MoE token is bounded: about 14.4-16 ms, and the bandwidth
estimate says a perfect kernel saves at most about 5 ms of that
(`the-xeon-memory-bandwidth-2026-10-25.md`; both are estimates, as that file states).
- Risk: medium. The results must be bit-identical to repeated `vec_dot` calls, which the patch's
  own contract already requires.

### 3.4 The drafter on the idle card (an app fix)

The beta.6 35B launch reads `dflash : off by memory planner (need 30.99 GiB, budget 10.5 GiB)`
(`gates-beta6/out/set/ornith-1.0-35b-Q6_K.fixed.applog:11`). There are two causes in the app
source:
- `Sources/Hardware/Hardware.swift:247-253` models expert placement only through `ncmoe`. Dynamic
  MoE launches without `--n-cpu-moe`, so `cpuFraction` is 0 and `baseWeightsGB` becomes the whole
  file (26.56 GiB). The planner thinks every expert is on the card.
- `Sources/Servers/Server.swift:432` disallows a draft whenever `usesAutoPlan` is set and the plan
  is not `full_gpu`, and whenever the placement is host (the comment at `:431` reads "A model on
  the host has no card for the draft to run on"). The 10-31 evidence ran exactly that case
  (35B at `-ngl 0`, drafter `-devd MTL0` on card 1), with byte-identical text.

**The fix.** On the expert tier (main model on card 1, `Server.swift:798-801`), plan the drafter
on the other card and budget it against that card alone. On host placement, plan it on a card.
Upstream #31506 ("dflash: copy hidden features via device copies", `2cbca389f`, after the pin)
touches the same cross-device path and should be read before the change.
- Expected effect: unknown until measured. The only observation is the host-target case above.
- Risk: the drafter would sit on card 0, the display card, which has a recorded slow mode while
  the display is awake (ticket 72).

### 3.5 Expert residency: keep the fork's policy; take two upstream pieces

Upstream added a GPU cache for experts kept in host memory after the pin (#29887 `d6cf9acb2`,
multi-GPU #30112 `c811cb8f0`, SLRU #30637 `33d6135cb`). Mechanically, in
`src/llama-moe-cache.cpp` at upstream HEAD:
- At each MoE layer it reads the router's selected ids back to the host and synchronises
  (`:566-567`).
- It uploads the misses with `ggml_backend_tensor_set_async` (`:585`).
- It computes every selected expert on the GPU.
- It refuses tensor split (`:268-270`).

On this machine a miss would cost a PCIe upload plus a sync per layer. The fork's Dynamic MoE
instead computes misses on the CPU while the card runs the resident ones (pooled-budget ticket
07: "not upstream's `--moe-cache-mib`, which uploads misses instead of computing them"). The
earlier survey's lever 2 (cafe-llama's copy overlap) applies to that upload design and to prefill,
not to this decode path. That is a correction to `engine-survey-2026-11-02.md`.

Two upstream pieces are worth taking:
- `MUL_MAT_ID` with index −1 skips the computation (#26631, `701fd25b3`).
- A batched tensor copy API (#30881, `418f905a4`), for arena uploads and prefill.

### 3.6 Prefill of host-placed dense models on a card

The pin's Metal backend accepts op offload for `MUL_MAT`/`MUL_MAT_ID` above a minimum batch
(`ggml/src/ggml-metal/ggml-metal.cpp:850-863`). So a model at `-ngl 0` with a card visible can
upload each weight once per ubatch and multiply on the GPU. The app's host placement hides the
cards (`usesGPUs`, `Sources/Servers/Server.swift:237`; environment at `:798-818`; ticket 67 "no
card in the environment").

Measured host prefill: 27B Q8_0 4.9964 tok/s (`the-27b-q8-0-on-this-machine-2026-10-20.md`); 27B
Q6_K 5.97 tok/s on an 856-token prompt (`the-dense-27b-across-host-one-card-and-both-cards-2026-10-22.md`).

**The mechanism.** Each ubatch moves the whole weight file over PCIe once. The gain grows with
`-ub`. The host-to-card rate on this Mac has never been measured: no file in the repo records
one, so the PCIe 3.0 x16 link rate is UNVERIFIED as a working number. Whether op offload was
already active in the rows above is also UNVERIFIED. The 27B cell ran with the default
environment, which registers card 0.

Ticket 3 below measures both, with `-nopo` as the control. CLAUDE.md rule 2 applies: first confirm
that offload happens, from the log or GPU activity, before reading the difference.

### 3.7 Two cards for one dense stream

Tensor split is the only mode in which both cards read weights at the same time for one token.
The fork has it (`mgpu/0015-0018`). The two modes are different constraints, not a speed pair
(CLAUDE.md). Two blockers stand before a dense model over 12 GB can use both cards plus the host:
- Ticket 68 (open): a dense model split across both cards with the rest on the host answers
  zeros (`the-dense-27b-across-host-one-card-and-both-cards-2026-10-22.md`, cells two24/two28).
- The measured card rates. On this box one card's Q6_K mat-vec (37-53 GB/s) and the host's read
  ceiling (51.6 GB/s) are of the same order. That is consistent with the one12 cell gaining only
  0.07 tok/s over the host. Moving dense layers to one card buys little until §3.1 moves the card
  rate.

### 3.8 KV cache

- Quantised KV is in (q8_0, q4_0, iq4_nl, q5_x, turbo2/3/4; `vendor/llama.cpp/common/arg.cpp:321-334`,
  `quant/0013`). With q8_0 the beta.6 fit formula gives the 14B a context of 30720; it was not
  launched.
- KV is a capacity lever here, not a speed lever. `FLASH_ATTN_EXT` is 1.162 ms of a 77.957 ms
  35B decode graph at c=4096 (one run, 48 tokens).
- Learned sparse attention exists in the fork for indexer models (`metal/0010`). Model-agnostic
  eviction schemes are not in the pin. Their arXiv IDs are given from memory and were not
  re-fetched: H2O 2306.14048, StreamingLLM 2309.17453, Quest 2406.10774.
- `-nkvo` keeps KV in host RAM and computes attention on the CPU. On this host that is bounded by
  the 51.6 GB/s read rate over the KV bytes per token. It is useful for capacity at short
  contexts, not for speed.

### 3.9 Upstream since the pin (681 commits, 2026-10-05 to 2026-11-04)

These are the relevant merged changes; everything else is SYCL, Hexagon, CUDA, Vulkan, OpenCL, SVE
or s390x work:
- **LFM3:** #31252 `19cce6919` (LFM3-1.7B, LFM3-VL-2B, 2026-10-27). It builds on #30874
  `84e66d032`, the shared LFM base (`src/models/lfm-base.cpp`), which postdates the pin. The text
  model needs `src/models/lfm3.cpp`, `llama-arch`, `llama-model` and `gguf-py`. The pin already
  has `build_inp_mem_hybrid_iswa` (`src/llama-graph.h:1433`) and `wqkv_gate`
  (`src/llama-model.h:310`). Follow-ups: #31431 `bc428e407` (tensor split for LFM3), #31598,
  #31608, #31257 (audio/omni).
- **MoE:** the GPU expert cache (§3.5); #26631 (−1 index skip); #30861 (MoE down projection
  scaled per expert token); #30373 (Metal `mul_mat_id` with duplicate ids); #30795
  (`moe_reduce` fusion race). The fork's `metal/0057` already carries the #30795 fix: its first
  hunk is that overlap check.
- **Metal:** #30065 few-row MMA mat-mul (UNVERIFIED: whether it compiles or is selected on GCN;
  the diff was not read); #31075 faster MXFP4 mat-vec and full threadgroups for unary/binary/GLU
  (the fork's `metal/0076` already does the second half); #30072 overflow in large output
  offsets; #31581 cpy into non-contiguous dst; #29340 excess threadgroup memory in quantised FA.
  The last two are correctness fixes worth checking against the fork.
- **CPU x86:** nothing for AVX1. #30447 (Q2_0 dot) and #30296 (tiled accumulators) are AVX2-only.
  #30270 turned on F16C for scalar FP16 conversion and was partly reverted by #30342 after "45-65%
  slower Q8_0/Q4_0 MUL_MAT_ID kernels". That figure is from the commit message, and its hardware
  is not stated. The pin already uses the lookup table for FP16->FP32 on x86
  (`ggml-cpu/simd-mappings.h:58-64` defines only the compute macros; `:150-158` falls back to the
  table). Take neither commit, or both.
- **Speculative:** #30141 (MTP hidden state save/restore), #31506 (DFlash hidden features by
  device copy), #30459 `--spec-draft-n-ubatch`, #22055 (persistent n-gram cache).
- **Graph reuse** is already in the pin (`src/llama-context.cpp:382`, `:1618`).
- **Fit:** #29677 (even split when no device reports free memory). The fit itself is unchanged
  in scope; ticket 76 already covers it.

## 4. Ruled out

| candidate | precise blocker |
|---|---|
| ik_llama.cpp (IQK quants, `-rtr` repack, fused MoE on CPU, MLA CPU path) | `ggml/src/iqk/iqk_config.h:13`: `#if defined __AVX2__ \|\| defined __ARM_FEATURE_DOTPROD` → `#define IQK_IMPLEMENT`. Every `iqk_gemm_*.h` is `#ifdef IQK_IMPLEMENT`. `README.md:13-14`: the only functional backends are CPU (AVX2 or NEON) and CUDA, and issues about "Metal ... `AVX` CPUs" "will not get resolved". This corrects the 11-02 survey's receipt (fork mirrors; "AVX2 + FMA3"): the gate in code is `__AVX2__`. |
| KTransformers / kt-kernel | `docker/README-packaging.md:272-274`: the CPU variants are AMX, AVX512 and AVX2, and AVX2 is "maximum compatibility". The expert-scheduling tutorial requires "x86 CPU with AVX512" and an RTX 4090 (`doc/en/kt-kernel/experts-sched-Tutorial.md`, Hardware Requirements). The GPU side is CUDA/ROCm/XPU (`README.md:51,55`). |
| PowerInfer | `README.md:81-83`: x86-64 with AVX2 (Linux/Windows), or Apple M chips CPU-only on macOS. Metal is a roadmap item (`README.md:87`, `:296`). It needs ReLU-sparsified models plus predictor weights (`README.md:139`, `:205`). The paper's 11.69x is against llama.cpp on an RTX 4090 (arXiv 2312.12456). |
| PowerInfer-2 | arXiv 2406.06282: a smartphone framework; the README's 11.68 tok/s for TurboSparse-Mixtral-47B is a phone figure (`README.md:15`). No x86/Metal-on-AMD path in the repo. |
| T-MAC | `python/t_mac/intrins/tbl.cc:4-6`: `#ifdef __ARM_NEON ... #elif defined __AVX2__`, with no other path. x86 targets are `-mcpu=core-avx2` (`python/t_mac/platform.py:113,125`). The paper's numbers are M2-Ultra and Raspberry Pi 5 (arXiv 2407.00088). |
| BitNet.cpp | `src/ggml-bitnet-mad.cpp:199`: the I2_S dot is `#if defined(__AVX2__)` (256-bit integer shifts). The TL2 preset kernels are `#ifdef __AVX2__`. Ternary weights already run through the fork's own `quant/0014` types. |
| llamafile `iqk_mixmul` | `llamafile/sgemm.cpp:65-113`: `iqk_mixmul` is set only on the FMA (+F16C) and AVX2 branches. Ivy Bridge gets `llamafile_sgemm_amd_avx` / `llamafile_mixmul_amd_avx` with no iqk. The AVX sgemm is already in the pin. |
| MLX | install docs: "Using Apple silicon", macOS >= 14; "Building for x86_64 on macOS is not supported" is listed as a build error. |
| vLLM (CPU) | CPU install docs: "`avx512f` (Recommended), `avx2` (Limited features)"; macOS is "experimental support ... with Apple Silicon". |
| ExLlamaV2/V3 | README: "PyTorch ... CUDA 12.4 or later"; minimum CUDA 12.4. |
| SGLang | CUDA/ROCm serving stack; recorded in pooled-budget ticket 04, not re-fetched here. |
| TensorRT-LLM | NVIDIA-only by design; not re-fetched. |
| MLC-LLM / TVM Metal | Not strictly ruled out (UNVERIFIED). Its tensor parallelism needs a collective library (UNVERIFIED for Metal), it does not read GGUF, and it would add no mechanism our Metal kernels lack. |
| FlexGen as code | PyTorch/CUDA. Its target is "latency-insensitive tasks with batched processing", "effective batch size of 144" on a single 16 GB GPU (arXiv 2303.06865). Batch-1 chat is the opposite regime. |
| Dense-weight streaming RAM→GPU for decode (AirLLM / FlexGen style) | Each token would move the whole weight file over the bus, while the host reads it at a measured 51.6 GB/s. The bus rate is unmeasured, but PCIe 3.0 x16 is below DDR3 x4 on paper. Only prefill (§3.6) amortises the upload. |
| Strata, AirLLM, uzu, magnitude | `third-party-receipts-2026-10-21.md`, `uzu-and-magnitude-on-this-mac-2026-10-29.md` (unchanged). |

## 5. The beta.6 "Not covered" list

| item (dist/beta31b6-notes.md) | concrete fix, or why it stays |
|---|---|
| LFM3-1.7B does not load (`unknown model architecture: 'lfm3'`) | Backport upstream #30874 (`84e66d032`, LFM base) and #31252 (`19cce6919`, text model only) as a new `patches/llama/model/` patch. Optionally add #31431 for tensor split. Gate: `test-backend-ops` on both cards, the stress cells, and `test-llama-archs` if it builds at the pin. The gate run already holds an `LFM3-1.7B-F16` prefill CSV (`gates-beta6/out/pp-LFM3-1.7B-F16-c*.csv`), so the model file is on disk. |
| A tensor split of Ternary-Bonsai-2-27B PQ2_0 cannot run (exit 86) | Stays. The engine refuses `RESHAPE` on a tensor-split prism tensor by design, and the app's layer split serves the model with byte-identical text. A fix would need split-aware reshape in the meta backend for the prism types, for a model that already serves. |
| The 35B's DFlash drafter is not used on the expert tier | App fix (§3.4): `Sources/Hardware/Hardware.swift:247-253` (ncmoe-only expert model) and `Sources/Servers/Server.swift:432` (draft gate). Plan the drafter on the card the expert tier does not use. Shortlist ticket 1. |
| Two parallel requests not tested (`--parallel 1`) | Add a stress cell with a separate `--parallel 2` launch. It does not change what the app ships. Upstream #29510 (`1b6935b22`, `flash_attn_ext_rows`, unified KV for multi-seq) postdates the pin and is the relevant engine change if parallel slots ever ship. |
| A 32-lane GPU: there is none here | Stays. It needs hardware. The D700 rules sit inside `simd_width == 64` checks, so a 32-lane run is the only real test. |
| The throughput table ran with an idle CPU-only 14B server resident | Fix the procedure: the bench step refuses to start while another `llama-server` process exists (a `pgrep` check; whether the stress script already has one was not checked), then re-run the two rows. |
| The real chat went through the engine API, not the chat window | Stays as a human gate: a person reads one answer in the window. UI automation of the chat window does not exist in this repo. |
| First-token logprobs, GPU against CPU, reported not gated | Gate on top-1 agreement over a fixed prompt set, plus a bound on the logprob difference set from the measured spread between two CPU runs (the noise floor, CLAUDE.md rule 3). Never gate on byte equality: the backends sum in different orders. |
| The tag is annotated, not signed | Stays until the owner provides a signing key. An agent cannot sign as the owner. |

## 6. Shortlist (ranked)

Every gate uses one method line format:
- engine and the release sha256, llama.cpp `d81235049` plus N patches;
- model and quant;
- `-c`, `-b`/`-ub`, `-t`;
- card index;
- N and whether warmups are discarded.

No ratio against a vendor or modelled figure (CLAUDE.md rule 1). The control in each A/B must
first be shown to take effect (rule 2).

1. **The DFlash drafter on the idle card for the expert tier and host placement** (app).
   - Files: `Sources/Hardware/Hardware.swift:228-279` (`DflashMemoryPlanner`: take the Dynamic MoE
     resident bytes from the engine's plan instead of `ncmoe`), `Sources/Servers/Server.swift:428-438`
     (draft gate), `:798-801` (card choice), plus app tests.
   - Gate:
     - Ornith-1.0-35B Q6_K with the app's launch (`-c 32768 --dynamic-moe on`, expert tier on
       card 1), drafter `-devd MTL0`.
     - 6 alternating servers (drafter / no drafter), 1 warmup + 3 measured requests each, the BST
       prompt, 128 tokens, greedy.
     - Report decode tok/s, accepted/drafted and draft ms. Text must be byte-identical to no
       drafter.
     - The log must show `dflash` enabled with an `ngld` and per-device buffers on both cards.
     - Record whether the display was awake (ticket 72).
2. **The card's read ceiling, then a type sweep, before any GCN mat-vec layout work.**
   - Files: ticket 19's kernel under `tools/` or `tests/`; `tests/test-backend-ops.cpp` perf cases
     (patch `moe/0070` already adds the dense shapes).
   - Gate:
     - A read-only Metal kernel over a buffer of at least 1 GiB on card 1, at least 1 s soak, N=5
       processes. Report GB/s with buffer size and sd.
     - Then `test-backend-ops perf -o MUL_MAT -b MTL0` for q4_0, q8_0, iq4_nl, q4_K, q5_K and q6_K
       at the 35B and 8B shapes, pipelines confirmed with `TOSH_SWEEP_DEBUG=1`, N=5.
     - Then the per-op decode table (`TOSH_OPGPU=1`, `moe/0049`) re-taken on beta.6.
     - Only if the simple formats or the ceiling show room: a repacked buffer type for Q6_K/Q4_K
       mat-vec in a new `patches/llama/metal/` patch, gated by `test-backend-ops` 0 failures on
       both cards and 35B/8B decode N>=6 against the unrepacked build in the same session.
3. **GPU prefill for host-placed dense models (op offload) and the PCIe rate.**
   - Files: none, to measure. If it pays: `Sources/Servers/Server.swift:237` and `:798-818`, so that
     host placement keeps one card visible for offload.
   - Gate:
     - 27B Q8_0 at `-ngl 0`, `llama-bench -p 2048 -n 0 -r 3` at `-ub {512,1024,2048}`, with and
       without `-nopo`, card 1 visible, `GGML_METAL_DEVICE_INDEX=1`.
     - Confirm offload from GPU activity (`ioreg` Device Utilization) or the per-op log. If the
       `-nopo` cell shows identical GPU activity, the control is inert and the run is void.
     - Report the host-to-card copy rate separately: a timed `ggml_backend_tensor_set` of 1 GiB,
       N=5.
     - Decode text unchanged.
4. **An AVX1 port of the `core/0022` multi-row dots (Q6_K, Q4_K, Q8_0 first), preceded by the
   verify-cost curve.**
   - Files: `patches/llama/core/0022-cpu-expert-dots.patch` (an `#elif defined(__AVX__)` branch
     beside lines 1454-1477), `ggml/src/ggml-cpu/arch/x86/quants.c`.
   - Gate:
     - Step 0: `llama-bench -ngl 0 -p 1,2,4,8 -n 0 -r 5` on the 35B Q6_K and the 27B Q8_0, with
       `GGML_CPU_NO_MULTI_DOT` unset and set. On today's AVX1 engine the two must be identical,
       which proves the switch is inert today.
     - After the port: the same cells, the switch now changing the path (confirmed by a log line),
       `test-backend-ops -b CPU` 0 failures, and 0 AVX2/FMA mnemonics in the built binaries.
5. **Backport LFM3** (#30874 + #31252, then #31431).
   - Files: a new `patches/llama/model/` patch touching `src/models/lfm-base.cpp`,
     `src/models/lfm3.cpp`, `src/models/lfm2.cpp`, `src/models/models.h`, `src/llama-arch.*`,
     `src/llama-model.cpp`, `src/llama-quant.cpp`, `gguf-py/`.
   - Gate:
     - The series applies at the pin (`scripts/check-patch-series.sh`).
     - LFM3-1.7B F16 loads on each card and on the host.
     - The stress cells of the release contract pass.
     - `llama-bench -p 512 -n 128 -r 5 -fa 1` on card 1, with the method line.
6. **Ticket 68, the zeros on a dense model split across both cards plus host** (bug; it blocks
   §3.7).
   - Files: the mixed-placement path in `src/llama-graph.cpp` and the scheduler. The bisection
     method from ticket 71 / `moe/0053` (a fusion switched off by environment) is the first probe.
   - Gate: 27B Q6_K, cells two24/two28 from the 10-22 evidence, text identical to the host
     reference for 400 tokens, N=4 per cell, both cards' buffers in the log.
