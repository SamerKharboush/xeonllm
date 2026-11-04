# 03: which newer engines and methods beat llama.cpp, and which of their ideas fit this machine

Answers `../issues/03-which-newer-engines-and-methods-beat-llama-cpp-and-why.md`. It builds on
`.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` (called "the survey" below) and
does not repeat what the survey settles. Nothing was built, run or benchmarked for this note.
Every "measured here" number comes from an existing evidence file in this repo, named next to it.

**The machine.** Mac Pro 6,1:
- Xeon E5-2697 v2: AVX and F16C, no AVX2 or FMA;
- 64 GB DDR3, host read ceiling 51.6 GB/s;
- 2x FirePro D700: GCN 1.0, 64 lanes, Metal only, no peer link.

**Card 1 caveat.** On 2026-11-04 card 1 failed basic op tests that it passed on 2026-11-03
(`../issues/01-is-card-1-healthy-after-a-cold-power-cycle.md`). Every card-1 number taken on
11-04 is suspect until ticket 01 resolves:
- the 204.4-206.1 GB/s read ceiling;
- decode at 37.1-51.5 GB/s of model bytes;
- the 10.98-11.25 GB/s host-to-card copy;
- the "offloaded mat-mul computes garbage" verdict (beta7 tickets 02, 03, 08).

The host t(k) curve (beta7 ticket 04, no GPU work) is not affected. Neither are the card-1
measurements from before 11-04: the 10-25 Dynamic MoE token split and the 10-30 `nr0` sweep. No
card-0 replacement of the 11-04 numbers exists. Where a number below is card-1/11-04 it says so.

## Sources (read 2026-11-04/05, blobless clones under `~/Library/Caches/beta8-research/`)

| repo | commit |
|---|---|
| ggml-org/llama.cpp (upstream HEAD) | `3de52ac38818978d6da8f386eda43a856e53714a` (10 commits after the survey's `cd959bae9`, none relevant: SYCL, WebGPU, OpenCL, UI, TTS, CI) |
| pin, as patched in `vendor/llama.cpp` | `d81235049384534c167caea52b85a694f6103d14` |
| ikawrakow/ik_llama.cpp | `009dce19afdd3f1e4b5039bcd8853256726c322b` (newer than the survey's `7cfc9ed`) |
| FasterDecoding/TEAL | `fb7373c93ac3594817c9ee64d4e08b47430a1822` |
| ScalingIntelligence/CATS | `679959c3323790be0a7d7d9af78e0580f8b88ed8` |
| FMInference/DejaVu | `ee902c1a452d6fe9be6e917cae53b15087361945` |
| SJTU-IPADS/PowerInfer | `8bd56d69906c9d2dba4d3bf6899763401e01a9a4` |
| Cornell-RelaxML/qtip | `e90c6688c8dfae326a3a81b5eb032db7c6680ec0` |
| turboderp-org/exllamav3 | `bd1f519172406a9560bd5c90e61000691bb69a07` |
| microsoft/T-MAC | `7042f8f73330bd083bc1e4bc5ccb3f88a4904aee` |
| SafeAILab/EAGLE | `cb7e0841fe0c206c6ed74a197ad5e2a1f13f5a2b` |
| hao-ai-lab/LookaheadDecoding | `eed010da9c7b1867912675d480feec5629e0c2d0` |
| facebookresearch/LayerSkip | `494752e5fbb0a82989f6cb384841684b1c2ef5c3` |
| prabanta-dev/janas | `71f65eab89f411223baf644ab81dccaa8f84cb5c` (2026-11-04) |
| brontoguana/krasis | `276973691b41850e9215ddd2f3bbd1a8099bfd0b` |
| lucienhuangfu/eLLM | `5df8de26ed42f550ccd53f05309928192eb1cbde` |

Papers:
- arXiv abstract pages: TEAL 2408.14690, CATS 2404.08763, Lookahead 2402.02057, MARLIN 2408.11743.
- KTransformers, SOSP '25 (DOI 10.1145/3731569.3764843), full PDF from the MadSys site; its text
  was extracted locally.
- EAGLE-3 (2503.01840), T-MAC (2407.00088) and PowerInfer (2312.12456) are cited through the
  survey and their repos.

## 1. The answer

No engine from 2025-2026 that is reported faster than llama.cpp runs on this machine. Every such
engine needs at least one of these:
- AVX2 or newer: janas, ik_llama.cpp, T-MAC, BitNet, eLLM (AVX-512 FP16);
- CUDA: krasis, ExLlamaV3, QTIP, KTransformers' GPU side;
- Linux or Windows with Vulkan: janas says "macOS (not supported)";
- trained predictor or draft weights: PowerInfer, Deja Vu, LayerSkip.

Their ideas can still be built here, and three of them gain from the newer numbers:
1. **The GCN decode mat-vec is the largest lever.** It moves 37-52 GB/s of model bytes while the
   card reads about 205 GB/s, both card 1 on 11-04. A back-of-envelope count says the kernel is
   bound neither by memory nor by ALU, so a repacked layout is the tool. Upstream's own Vulkan
   tuning for GCN backs this: `ggml-vulkan.cpp:2879-2882` and `:6687-6691`, where "q6_k only has
   2-byte alignment which makes it somewhat problematic".
2. **Speculation re-tuned to the measured verify curve.** t(2)/t(1) is about 1.4 on the host. So
   a 1-3 token draft from the MTP heads already on disk breaks even at modest acceptance. The
   pin's n-gram defaults of 48-64 token drafts (`common/common.h:360-366`) are wrong for a host
   where t(8) is 4-6 x t(1).
3. **Overlap of the CPU experts with card work in Dynamic MoE.** Today each ms of the 14.4 ms of
   CPU experts adds a ms to a 76 ms 35B token (10-25 split). The lossy extreme of this is
   KTransformers' Expert Deferral (SOSP '25). A lossless overlap inside the layer comes first.

Activation sparsity (TEAL, CATS) and LUT/trellis quants transfer only as large rewrites: a
transposed down projection with an AVX1 axpy, or new GGUF types. Their effect here is bounded by
the bytes they skip, and their quality has never been checked on the Qwen3/Gemma 4 models used
here. Layer skipping and lookahead lose on this verify curve, from the mechanism.

Where the newer sources change the survey:
- The verify curve is sub-linear, not linear (beta7 04). This moves speculation up the ranking.
- The pin has **no AVX1 path at all** for the TQ1_0, TQ2_0, Q2_0, PQ2_0 and PTQ1_0 dots. That is
  the gap T-MAC and BitNet fill on AVX2.
- KTransformers' scheduling idea is portable, though its code is not.
- ik_llama.cpp ships Metal trellis kernels, even though its README disowns Metal.
- The "offload computes garbage" verdict was measured on the failing card 1 and must be redone
  on card 0.

## 2. Ranked table (expected effect on this machine, from mechanism)

| # | idea | source | runs here? (+blocker) | already in pin/fork? | expected effect, from mechanism | effort / risk |
|---|---|---|---|---|---|---|
| 1 | GCN mat-vec repacked for 64-lane 16-byte coalesced loads (Q6_K, Q4_K first) | upstream Vulkan GCN tuning `ggml-vulkan.cpp:2879-2882`, `:6687-6691`; ik `-rtr`; MARLIN 2408.11743 (offline repack for coalesced loads, NVIDIA) | yes (Metal buffers + kernels) | no. Fork has aligned word reads (`metal/0003`, `0060`), `nr0=8` (`0071`, `0074`), short rows (`0065`) | every card-resident token. Decode moves 37-52 GB/s of bytes; a streaming read reaches ~205 GB/s (card 1, 11-04). The size is unknown until built. Ceiling to be re-taken on card 0 | high: a second layout seen by every kernel of the type; ticket 07 |
| 2 | Speculation with short drafts sized to t(k): MTP head, DFlash, EAGLE-3, n-gram at `n_max` 1-3 | beta7 ticket 04 curve; pin `common/common.h:328-366`; EAGLE `cnets.py:487` (reduced draft vocab) | yes | pin: all types; fork `spec/0028`, `0040`, `0073`; MTP GGUFs on disk | host-placed models. Break-even acceptance about 0.45 at k=1 and about 0.6 at k=3 (§3.2). n-gram defaults (48-64 drafted) sit where t(8) is already 4.0-5.9 x t(1) | low: flags and app; text must stay byte-identical (greedy) |
| 3 | Overlap of CPU experts with card work in Dynamic MoE (lossless), then KTransformers' Expert Deferral (lossy) | KTransformers SOSP '25 §1, Fig. 1c; 10-25 token split | yes (Metal + CPU threads) | partial: `moe/0063` runs the shared expert during host experts, yet the slope is 0.976 ms per ms | at most H = 14.4 ms of a 76.0 ms 35B token (card 1, 10-25). Deferral is lossy: the paper reports ≤0.5% average accuracy drop | medium (lossless) to high (deferral changes the model: a quality gate, not byte identity) |
| 4 | AVX1 multi-row dots (`core/0022` port) | ik_llama `iqk_gemm_*`; fork `core/0022` | yes, 128-bit integer | AVX2-only in fork | lowers t(k≥2) on the host. For the dense 12B t(2) = 1.47 x t(1) and the extra is compute; for the 35B part of it is more experts read | medium; beta7 ticket 04 is ready |
| 5 | Op offload prefill of host weights | pin `ggml-metal.cpp:850-863`; scheduler fix in beta7 `evidence/03/` | blocked: garbage text, **measured only on card 1 on 11-04** | pin (inert by scheduler bug) | host prefill 10.07-11.80 vs 20.89-22.05 tok/s offloaded, gemma4 12B Q8_0, card 1, 11-04. Valid only once the text is right | low to re-test on card 0; ticket 08 |
| 6 | CATS/TEAL-style FFN activation sparsity on the host (skip rows of `up`, rows of a transposed `down`) | CATS repo `flash_gemv/` (L40S); TEAL `kernels/sparse_gemv.py:86,106`; PowerInfer `ggml.c:14285-14312`, `llama.cpp:4635` | yes in principle; needs a transposed `down`, an AVX1 axpy, and thresholds calibrated per model | no | host-bound dense decode only: fewer FFN bytes. For Qwen3-8B shapes at 50% sparsity, up+down skip 50.3M of 193M weights per layer (§3.5). Quality unmeasured on these models | high, lossy. TEAL README:111 says quantized kernels are not supported |
| 7 | SSSE3/AVX1 kernels for ternary and 2-bit types (T-MAC's `pshufb` LUT idea at 128 bits) | pin `arch/x86/quants.c:1376-1740` (AVX2 or scalar only); T-MAC `tbl.cc:4-8` | yes | no: those types fall to scalar code here | only host-placed ternary/2-bit models; today Bonsai 27B PQ2_0 runs on the cards (beta4 notes: 6.18 tok/s layer split) | medium; narrow |
| 8 | KV compression or offload | survey §3.8; janas README:43-53 (AVX2 laptop) | yes | pin + fork (q8_0, q4_0, turbo) | capacity, not speed, at c ≤ 4096 (FA 1.16 ms of 78 ms). Long host contexts unmeasured here | low |
| 9 | Trellis quants (QTIP / ik IQ*_KT / EXL3) | qtip README:28-41; ik `ggml-metal.metal:6915-7287`; exl3 `quant/codebook.cuh` | ik's Metal kernels exist; types not in upstream GGUF | no | capacity per bit, not decode speed: the card is kernel-bound, not byte-bound, and the decode is a 32-bit integer multiply per weight | high: new type IDs, quantiser, models not upstream-compatible |
| 10 | Layer-skip / early-exit self-speculation | LayerSkip README:31,70; SWIFT (UNVERIFIED) | engine-side yes; needs LayerSkip-trained checkpoints | no | loses: a draft at about 0.5 t(1) needs acceptance above 0.9 at t(2)/t(1) = 1.42 (§3.6) | — |
| 11 | Lookahead (Jacobi) decoding | arXiv 2402.02057 (trades "per-step log(FLOPs)"); pin `examples/lookahead` | yes | pin | loses: it verifies large windows, and t(8) = 4.0-5.9 x t(1) here | — |
| 12 | Predictor-based sparsity (Deja Vu, PowerInfer) | DejaVu README:3 (OPT-175B, trained predictors); PowerInfer README:81-87 | no: trained predictors or ReLU models, CUDA/AVX2 | — | — | — |
| 13 | "Much faster" 2026 engines: janas, krasis, eLLM, Magnitude, cpubrrr, llama-modchip | repos above; web listings | **no** (§3.9) | — | — | — |

## 3. Per idea

### 3.1 The GCN mat-vec (rank 1)

**What changed since the survey.** The survey left this open ("unknown until ticket 19"). Beta7
ticket 02 measured it, on card 1 on 11-04:
- a read-only `read4` kernel: 204.4-206.1 GB/s;
- decode as model bytes x tok/s: 37.1 (Qwen3-0.6B Q8_0) to 51.5 GB/s (Qwen3-8B Q4_K_M).

These are two observations, not a ratio.

**Why the kernel, not the card or the ALU, is the limit (estimate, UNVERIFIED rates).**
- Qwen3-8B Q4_K_M at 10.249 tok/s means about 8.2e9 weights x 10.25 ≈ 84 G weights/s.
- At about 2 flops plus a few integer ops per weight, that is well under 1 T ops/s.
- The D700's vendor peak is 3.5 TFLOPS. It is used here only as a bound, never as a denominator.
- So the kernel is bound by neither ALU nor bytes. Latency, occupancy and load width are the
  remaining candidates, which is ticket 07's hypothesis.

**What newer primary sources say about GCN specifically.**
- **Upstream Vulkan sets more rows per workgroup on GCN than elsewhere:** `rm_stdq = 2`,
  `rm_kq = 4`, `rm_stdq_int = 4` (`ggml-vulkan.cpp:2879-2882` at `3de52ac38`). The fork's
  measured `r8_w64` win (53.12 against 42.85 GB/s, card 1, 10-30) points the same way.
- **Upstream refuses the integer-dot mat-vec for Q6_K on AMD:** "q6_k only has 2-byte alignment
  which makes it somewhat problematic, using MMVQ is only a win on Intel" (`:6687-6691`). Q6_K's
  210-byte block is the layout problem. It is also the type of the 35B's 311 dense mat-vecs
  (survey §3.1).
- **Repack-at-load is the established fix on other hardware:**
  - MARLIN (arXiv 2408.11743) reorders weights offline so that 4-bit GEMV/GEMM stays memory-bound
    on NVIDIA GPUs;
  - ik's `-rtr` and upstream `CPU_REPACK` do the same on CPUs (survey §3.1).

  None of these targets GCN or Metal. The idea transfers, the code does not.

**Expected effect.** Unknown until built. The bound is the card's read ceiling, to be re-measured
on card 0. Ticket 07 has the gate.

### 3.2 Speculation against the measured verify curve (rank 2)

**The measured curve** (beta7 04, shipped AVX1 engine, `-ngl 0 -nopo 1 -t 12`, N=5, warmup
discarded by llama-bench, idle 14B server resident):

| model | t(2)/t(1) | t(4)/t(1) | t(8)/t(1) |
|---|---|---|---|
| Ornith-1.0-35B Q6_K | 1.42 | 2.16 | 5.91 |
| gemma4-coding 12B Q8_0 | 1.47 | 2.26 | 4.03 |

**The mechanism.** With k drafted tokens, a free draft and acceptance probability α per token,
one round costs t(k+1) and yields (1 - α^(k+1)) / (1 - α) tokens. Break-even against plain
decode, from the measured ratios:
- k=1: 1 + α = 1.42-1.47, so α ≈ 0.42-0.47;
- k=3: 1 + α + α² + α³ = 2.16-2.26, so α ≈ 0.6.

A drafter that costs d x t(1) per token raises these thresholds. This is algebra on the measured
t(k), not a measured speed. The t(k) are prompt-processing batches, and a real verify batch also
carries KV and sampling, so the thresholds are lower bounds (UNVERIFIED).

**What the sources add:**
- **N-gram defaults are mis-sized here.** `common_params_speculative_ngram_mod` defaults to
  `n_max = 64, n_min = 48`, and `ngram_map` proposes m-grams of `size_m = 48`
  (`vendor/llama.cpp/common/common.h:357-367`). On this host one 8-token verify already costs
  4.0-5.9 single tokens. Cap n-gram drafts at 1-3.
- **MTP heads are on disk:** `Qwen3.6-27B-...-MTP-Q6_K.gguf` and
  `Ornith-1.5-9B-GSQ-RCO-IQ3_M-mtp.gguf`.
  - The pin's draft default is `n_max = 3` (`common.h:329`), which sits on the sub-linear part of
    the curve.
  - Janas reports 74-89% of drafts kept on Qwen MTP blocks for an English chat reply (janas
    README:168). That is on an AVX2 laptop with sampling and a different engine. It is a hint for
    the gate, not an expectation.
- **EAGLE-3:**
  - Unofficial heads exist for Qwen3-4B/8B/14B (EAGLE README:162-167, all marked "No" for
    official).
  - The pin loads a reduced draft vocabulary through `d2t` (`src/models/eagle3.cpp:44-48`). EAGLE
    trains with `draft_vocab_size: 32000` (`eagle/traineagle3/config.json:23`), so the draft head
    reads about a fifth of a 151k-vocab output head.
  - Hardware behind EAGLE's quoted speedups: 2x RTX 3090 (README:63).
  - Converting those heads to GGUF is UNVERIFIED.
- **DFlash:** on the host target with the drafter on card 1, 12.53 tok/s against 10.93-11.09
  plain, in a different configuration (10-31, card 1 before the failure). The verify block length
  should also be capped by the t(k) curve. DFlash's block-length control in the pin was not
  checked (UNVERIFIED).

**Effect.** It applies to host-placed models: the 27B dense at 1.60-2.03 tok/s, and the 35B
host/expert tiers. Cards: the card verify curve has never been measured (§4 H4).

### 3.3 CPU-expert overlap, and Expert Deferral (rank 3)

**Measured** (10-25 split, Ornith-35B Q6_K, card 1 before the failure, 1182 tokens):
- token W = 76.05 ms;
- GPU busy span 73.40 ms;
- CPU experts H = 14.45 ms;
- each ms of H adds about 0.976 ms to the token (slope from pooled-budget ticket 01, inferred, not
  measured).

So the CPU experts are serialised with the card's work, even though `moe/0063` runs the shared
expert during them.

**KTransformers (SOSP '25), from the paper text:**
- Expert Deferral processes "only a subset of experts (immediate experts)" in each MoE layer.
- "the remaining experts (deferred experts) are scheduled concurrently with the computation of the
  subsequent layer (primarily the attention module)" (§1, Fig. 1c).
- On DeepSeek-V3 it moves CPU/GPU utilisation "from 74%/28% to 100%/37%", with "33% throughput
  increase in decode" and "up to 45%" across scenarios.
- "the average model accuracy drop remains within 0.5%".
- Hardware: dual Intel Xeon Platinum 8452Y (36 cores each, 1 TB DDR5, 220 GB/s intra-socket per
  the paper) with an A100 40 GB or RTX 4080 16 GB over PCIe 4.0 (§6.1).
- It is lossy: a deferred expert's output joins the residual one layer late.

The survey ruled KTransformers out as code (AVX2 floor, CUDA). Its scheduling idea needs neither.

**Effect bound here.** The token cannot shrink by more than H, about 14.4 ms of 76 ms, and only
if the card has concurrent work to cover it. Do the lossless step first: find why the card waits
at each join, with the per-layer timeline of `moe/0048`. Do deferral only behind a quality gate,
since text will not be byte-identical.

### 3.4 AVX1 multi-row dots and op-offload prefill (ranks 4, 5)

Both are already tickets (beta7 04 and 08). Two new points:
- **For the dense 12B, t(2) = 1.47 x t(1) at the same bytes.** The extra 0.47 x t(1) is compute,
  which is exactly what sharing the unpack across rows removes. For the 35B, more distinct experts
  per batch add bytes, so the port can recover less. The t(8) jump to 5.9x shows that.
- **Ticket 03's "garbage" was measured on card 1 on 11-04, the day card 1 failed ADD, MUL and
  RMS_NORM op tests.** The verdict that the offloaded mat-mul is wrong in the fork is therefore
  unproven. Run ticket 08's bisection on card 0 first.

### 3.5 Activation sparsity: TEAL, CATS, Deja Vu, PowerInfer (rank 6)

**Mechanisms, from source:**
- **TEAL.** It zeroes low-magnitude inputs to every linear layer, training-free. Its Triton GEMV
  "assumes that weight is column major" (`kernels/sparse_gemv.py:86`, asserted `:106`) and loads
  only the weight rows of non-zero inputs (`:76-77`). "Quantized sparse kernels are not currently
  supported" (README:111).
  - The abstract claims up to 1.53x and 1.8x decode at 40% and 50% sparsity on Llama-2/3 and
    Mistral.
  - The GPU behind those numbers is not on the abstract page (UNVERIFIED).
- **CATS.** It thresholds SiLU(gate) and skips the matching `up` rows and `down` columns. Its
  fused CUDA kernels are in `flash_gemv/csrc/cuda/fuse_gemv_cmp_cuda.cu`. The artifacts are named
  `llama7B-mlp-l40s-fp32` (NVIDIA L40S, fp32). The abstract reports "~15% improvement in wall-clock
  inference latency".
- **PowerInfer.** It computes the down projection as an axpy over a transposed weight
  (`llama.cpp:4635`, `ggml_axpy(ctx, w_t, ...)`). The x86 axpy is AVX2/FMA, with a scalar `#else`
  (`ggml.c:14292-14310`).
- **Deja Vu.** It needs trained per-layer predictors and was validated on OPT-175B (README:3).

**Why it is a rewrite in ggml.**
- A ggml weight row is contiguous along the input dimension, and quant blocks span 32 or 256
  inputs.
- **Output sparsity** (CATS on `gate` → skip `up` rows) maps to skipping whole rows. That is
  cheap here.
- **Input sparsity** (TEAL everywhere, CATS on `down`) skips scattered elements inside blocks.
  It saves no bytes unless a whole block is inactive. It needs a transposed, per-neuron-quantised
  `down` plus an axpy kernel.
- On AVX1 without FMA that axpy is a dequantise, a multiply and a separate add per weight. Whether
  12 cores keep up with 51.6 GB/s that way is UNVERIFIED.

**Bound.** For Qwen3-8B's published shapes (hidden 4096, FFN 12288, GQA 8 KV heads of 128;
UNVERIFIED against the file on disk):
- one layer holds about 41.9M attention and 151M FFN weights;
- at 50% FFN sparsity, `up` and `down` skip 50.3M of about 193M weights per layer;
- `gate` must still be read in full.

For a host-bound dense model, time follows bytes. Quality at those thresholds is unmeasured on
every model used here. The MoE experts are small and already sparse, so the bound is lower there.

### 3.6 Layer skipping, early exit, lookahead (ranks 10, 11)

- **LayerSkip.** "In order to observe speedup, you need to access LLMs that have been trained
  using the LayerSkip recipe" (README:31). None is on disk.
- **Training-free skipping (SWIFT and similar).** UNVERIFIED (not fetched). It drafts with a
  fraction of the layers, so the draft costs a sizeable share of t(1). With d ≈ 0.5 and k=1, a
  round costs 0.5 + 1.42 = 1.92 x t(1) for 1 + α tokens, so it needs α > 0.92. It loses.
- **Lookahead.** It verifies a Jacobi window plus n-gram candidates per step. Its abstract
  describes it as "trading per-step log(FLOPs)" for fewer steps and claims "up to 1.8x on
  MT-bench" (GPU unnamed on the abstract page). On a host where t(8) is 4.0-5.9 x t(1), large
  windows lose.

### 3.7 Low-bit LUT kernels and new quant formats (ranks 7, 9)

**Ternary and 2-bit dots have no AVX1 path in the pin.** In `vendor/llama.cpp/ggml/src/ggml-cpu/
arch/x86/quants.c` these dots are `#if defined(__AVX2__)` with a scalar `#else` and no `__AVX__`
branch:
- `tq1_0` (:1388/1500);
- `q2_0` (:1509/1555);
- `pq2_0` (:1587/1613);
- `ptq1_0` (:1619/1672);
- `tq2_0` (:1689/1735).

Every K-quant and IQ type does have one. The `pshufb` table lookup that T-MAC and BitNet TL2 run
at 256 bits (`T-MAC/python/t_mac/intrins/tbl.cc:4-8`, AVX2 or NEON only) exists at 128 bits in
SSSE3. This matters only for a ternary model placed on the host. Today Bonsai 27B PQ2_0 runs
layer-split on the cards.

**Trellis quants.**
- QTIP's kernels are CUDA `mma.sync` (`qtip-kernels/src/inference.cu:365`). Its speed table is on
  an RTX 6000 Ada (README:31).
- EXL3 decodes each weight with a 32-bit multiply plus `lop3`/`dp4a`
  (`exllamav3_ext/quant/codebook.cuh:5-10, 36-48, 67-96`). It is CUDA ≥ 12.4.
- ik_llama.cpp has Metal kernels for IQ2/3/4_KT (`ggml/src/ggml-metal.metal:6915-7287`): a
  multiply-add, mask and xor per 32-bit word, read as two halves. PR 475 notes IQ4_KT was disabled
  on Metal for "a bug that I don't find". ik's README says Metal issues "will not get resolved".
- GCN 1.0's 32-bit integer multiply rate and its lack of packed FP16 are UNVERIFIED here (AMD
  Southern Islands ISA not fetched).
- Since card decode is not byte-bound today (§3.1), fewer bits per weight buy capacity, not speed.

### 3.8 KV cache (rank 8)

Nothing newer changes the survey's §3.8 for card placements. One newer data point, for host
placement:
- At 8,192 tokens with a q8_0 KV cache on the CPU, janas measured llama.cpp decoding Qwen3-4B
  Q4_K_M at 4.9 tok/s against its own 18.2 (README:43-53).
- With llama.cpp's F16 cache the numbers were similar.
- Hardware: Core Ultra 9 185H (AVX2, FMA, AVX-VNNI), llama.cpp build `2b18470`.

This says host attention at long context can dominate. Whether it does on this fork's AVX1 build
is UNVERIFIED. It is a measurement to take before any KV work (§4 H8).

### 3.9 Engines claimed faster in 2026

| engine | claim (hardware) | blocker here |
|---|---|---|
| janas | Qwen3-Next-80B 26 against 3.0 tok/s for llama.cpp (Core Ultra 9 185H, Arc iGPU, NPU, NVMe; README:16, :147-150) | "macOS (not supported)" (`docs/hardware.md:57`); "AVX2 with FMA and F16C ... is needed for good speed" (`INSTALL.md:8`); GPU via Vulkan only. Its ideas (an expert cache with NVMe streaming) are ticket 02's scope |
| krasis | RTX PRO 6000 / RTX 5090 tables (README:113-117) | Rust/CUDA hot path (README:16-18) |
| eLLM | "Faster on CPUs Than on GPUs" | "CPU: AVX-512 FP16 support" (README:70) |
| Magnitude | 92% faster Metal decode (press) | already ruled out: `uzu-and-magnitude-on-this-mac-2026-10-29.md` |
| cpubrrr | 7.5x on M4 Max (web listing only) | UNVERIFIED; NEON/SME by its listing |
| llama-modchip | 20-60 tok/s for a 30B MoE on CPU | AVX-512 VNNI by its own description (GitHub topic page) |

## 4. Candidate beta-8 hypotheses with gates

Every gate carries a method line: engine and release sha256, `d81235049` + N patches, model and
quantisation, `-c`, `-b`/`-ub`, `-t`, card index, N, and whether warmups were discarded. The rules:
- no ratio against the read ceiling or a vendor figure (rule 1);
- every switch is shown to take effect before its difference is read (rule 2);
- a spread larger than the noise is reported as separate observations (rule 3);
- every configuration that cannot run is named (rule 4).

**H0. Card 0 baselines replace the suspect card-1 numbers** (prerequisite for H1, H4, H5).
- `tools/metal-probe/readceiling.swift` and `hostcopy.swift` on card 0, N=5 processes, at most
  0.2 s per command buffer.
- `llama-bench -ngl 99 -p 0 -n 128 -r 5 -fa 1` with `GGML_METAL_DEVICE_INDEX=0`, for Qwen3-0.6B
  Q8_0, 4B Q4_K_M/Q6_K and 8B Q4_K_M.
- Record whether the display was awake (ticket 72).

**H1. A repacked Q6_K/Q4_K GCN mat-vec raises card decode** (beta7 ticket 07).
- Gate: `test-backend-ops` 0 failures on each healthy card.
- `llama-bench -p 0 -n 128 -r 5 -fa 1` on card 0, N ≥ 6 processes alternating with the
  unrepacked build in one session, 4B Q6_K and 8B Q4_K_M.
- Greedy text byte-identical over 256 tokens.
- Report tok/s and bytes x tok/s beside the H0 ceiling as two observations.

**H2. Short drafts pay on the host.**
- Qwen3.6-27B MTP Q6_K at `-ngl 0 -nopo 1 -t 12 -c 4096`, `--spec-type mtp`,
  `--spec-draft-n-max ∈ {1,2,3}` against none.
- 6 alternating servers per cell, 1 warmup and 3 measured requests, 128 tokens greedy.
- Control: the log shows drafted > 0 and accepted counts. Text byte-identical to no draft.
- Report tok/s and the acceptance rate, and compare α with the break-even values of §3.2.

**H3. N-gram drafts capped at 1-3 against the pin's 48-64 defaults**, on a code-edit prompt that
repeats its input.
- Host 12B Q8_0 and 35B Q6_K at `-ngl 0`. Same N, same control and same text rule as H2.

**H4. The card verify curve.**
- `llama-bench -ngl 99 -p 1,2,4,8 -n 0 -r 5` on card 0 for 4B Q6_K and 8B Q4_K_M.
- Record t(k)/t(1). It decides H2/H3 for card placements.

**H5. Lossless overlap of CPU experts with card work.**
- First the per-layer `TOSH_DMOE_TIMELINE` (`moe/0048`) for the 35B on card 0, N = 4 servers,
  warmup dropped, to name where the card waits.
- Gate for a fix: the slope of token time against H falls below 0.976 by more than its CI.
- Token ms N ≥ 6 servers alternating against the unfixed build. Text byte-identical.
- Expert Deferral only afterwards, with gates on top-1 agreement over a fixed prompt set and a
  logprob bound set from two CPU runs (the noise floor).

**H6. Ticket 08 re-run on card 0.**
- If op-offload text is right there, the 11-04 verdict was card 1's fault.
- Gate as in ticket 08: greedy text over 64 tokens on three models agrees with the host within the
  measured CPU-vs-GPU noise.
- Then the ticket 03 A/B on card 0: gemma4 12B Q8_0 at `-ngl 0 -p 1024 -n 0 -ub {512,1024} -r 3`,
  with the scheduler fix on and `-nopo` shown to change the split count (`GGML_SCHED_DEBUG=2`).

**H7. The AVX1 multi-row dots lower t(2..4)** (beta7 ticket 04 gate, unchanged).

**H8. Host attention at long context.**
- `llama-bench -ngl 0 -nopo 1 -t 12 -fa 1 -p 0 -n 64 -d {1024,4096,8192} -ctk {f16,q8_0}
  -ctv {f16,q8_0} -r 3` on Qwen3-4B Q4_K_M.
- Only if decode at `-d 8192` falls well below `-d 1024` beyond the noise is a KV/attention ticket
  opened.

**H9 (research only, lossy). CATS-style FFN sparsity on the host.**
- Step 1 is offline: dump SiLU(gate) magnitudes on a fixed prompt set for Qwen3-8B and gemma4 12B.
  Report the fraction below each threshold, and how many whole 32- and 256-wide blocks it zeroes.
- Proceed only if top-1 agreement against dense, at the thresholds giving 40-50%, stays within the
  CPU-run noise floor.

**Not proposed:**
- layer-skip self-speculation and lookahead (they lose on this curve, §3.6);
- trellis types (capacity only);
- the engines of §3.9.
