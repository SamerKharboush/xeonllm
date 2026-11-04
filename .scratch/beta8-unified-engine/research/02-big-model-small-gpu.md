# 02: What the big-model-on-small-GPU projects actually do, and what of it runs here

Research ticket: `.scratch/beta8-unified-engine/issues/02-what-do-the-big-model-on-small-gpu-projects-actually-do.md`.
Builds on and does not repeat:
- `.scratch/firellama-maxperf/evidence/strata-policy-not-code-2026-10-20.md`;
- `third-party-receipts-2026-10-21.md` (Strata, AirLLM and Colibri receipts at their 10-21 commits);
- `engine-survey-2026-11-04.md` (ik_llama, KTransformers, PowerInfer, T-MAC, BitNet, llamafile, MLX, vLLM, ExLlama,
  FlexGen, "LLM in a flash", upstream's `--moe-cache-mib`).

**Method.** Nothing was built, run or benchmarked. Shallow clones were made on 2026-11-04/05 under
`/Users/sam/Library/Caches/beta8-research/`. They were read only. Papers were read from their arXiv abstract or HTML
pages. Every "measured here" number comes from an earlier evidence file in this repo, which is named next to it.
Third-party numbers are quoted together with the hardware they were measured on, and none of them is offered as an
expected result here.

| repo | commit read | commit date |
|---|---|---|
| FlashML-org/FreeToken | `dac018e90b8e62318dba2af65529345bf06befdd` | 2026-11-04 |
| Mesh-LLM/mesh-llm | `14f7b9ffddfe375786dff58a4f647b25e1d9ee09` | 2026-11-04 |
| JustVugg/colibri | `0a5504a1dc64f86fcd0fe7db298b0448c730e7e6` | 2026-10-31 (receipts were at `e0db083`) |
| lyogavin/airllm | `ae4b00df2b5bafddf060b01bcd3ddecd3031f3b0` | 2026-11-04 (receipts were at `22d72c4`) |
| Niko1221/Strata | `ffa80d73133ea5c548aefe57889a16e8085a938f` | 2026-11-02 (receipts were at `011c9e6`) |
| yalun753/moe-l2 | `3b17ede0001d51dcf8ca1d8f3b0f74fbffb740c6` | 2026-10-01 |
| danveloper/flash-moe | `3601d41882a346d85041f7955c66429d248e8cd9` | 2026-03-19 |
| Lizonghang/prima.cpp | not cloned: `git clone` returned "repository not found". Read from arXiv 2504.08791v2 only | — |

**This machine, as measured in this repo:**
- Host read ceiling 51.6 GB/s (`the-xeon-memory-bandwidth-2026-10-25.md`).
- One D700 reads 204.4-206.1 GB/s with a plain streaming kernel (beta7 ticket 02, cited in beta7 ticket 07).
- Host-to-card copy, card 1: 10.98-11.25 GB/s wall time. That is a blit from a shared buffer into a private one,
  1 GiB in 64 MiB command buffers, 5 processes x 5 reps (beta7 ticket 03, `evidence/03/hostcopy-card1.txt`).
- **The NVMe read rate has never been measured.** No file under `.scratch/` records one; a grep for "nvme" finds only
  the beta8 map and this ticket.
- Op offload of host weights to a card has never run correctly on this fork: it computes garbage (beta7 ticket 08,
  `needs-triage`).

## 1. Answer

None of the new projects runs here as shipped. **FreeToken** is CUDA 13 or ROCm on RDNA3/4, Linux only. **mesh-llm**'s
installer refuses Darwin/x86_64. **moe-l2** is CUDA-only. **flash-moe** is hard-wired to one model on Apple Silicon.
**AirLLM** and **Strata** are unchanged at their new HEADs: MLX-only on darwin, and "Intel Macs cannot run it".
**Colibri** is the only one that now has a Metal backend. That backend is written for unified memory: it wraps host
pages zero-copy in `MTLStorageModeShared` buffers. On a D700 that means weights are read over PCIe, not from VRAM.
"Cabilary" could not be identified. Colibri is the closest candidate, and it is already covered.

Mechanically, the projects do one of four things:
1. Keep hot experts on the GPU and cold ones in RAM, then copy or compute the misses (FreeToken, moe-l2, Colibri,
   Strata).
2. Stream experts or layers from SSD (flash-moe, Colibri, AirLLM, prima.cpp).
3. Split layers across machines (mesh-llm, prima.cpp).
4. Swap in lower-precision copies of cold experts (HOBBIT).

The fork's Dynamic MoE already does most of item 1:
- an LFU arena with decay on each card;
- CPU-computed misses;
- pread into a locked RAM cache;
- reading experts a layer ahead from disk;
- a CPU/GPU rendezvous through shared events.

So what is left is small and specific. Three ideas are new to this fork and portable:
- **(a) FreeToken's bandwidth-matched split of misses.** Copy a share `f = p/(p+c)` of the misses to the card and
  compute the rest on the CPU, instead of computing all of them on the CPU.
- **(b) A persisted expert-heat profile to warm-start the VRAM arena** (Colibri `HEAT_FILE`, moe-l2 router maps).
- **(c) mesh-llm's pipelined verify windows across layer-split stages.**

Two measurements decide the rest:
- **(d) how many distinct experts a k-token verify touches on the 35B**, because FreeToken measured 2.3-2.75x for 4
  tokens on other hardware;
- **(e) the NVMe and zero-copy rates on this Mac.**

Every bound below is built from this machine's measured rates. None is a borrowed speed-up.

## 2. Table

`p` = host-to-card copy rate (measured 10.98-11.25 GB/s). `c` = the CPU's effective expert-compute read rate in decode
(**unmeasured**; its upper bound is the 51.6 GB/s read ceiling). "Fork" = `patches/llama/` at pin `d81235049`.

| project | mechanism | requirements | runs here? | portable idea for this fork | expected effect from mechanism | effort / risk |
|---|---|---|---|---|---|---|
| **FreeToken** (UC Berkeley / FlashML, arXiv 2608.16157) | MoE: dense weights and an LRU expert-slot cache on the GPU, every expert pinned in host RAM. Misses are copied (`offload`), computed on the CPU (`cpu`), or split between the two (`hybrid`, `f = p/(p+c)`). Prefill double-buffers whole layers | Linux x86_64, NVIDIA driver r580+/CUDA 13 (`docs/install.md:5-8`); or ROCm 7.14 on gfx1100-1201 (`docs/install_amd.md:9-12`); torch 2.14, Triton on Linux (`pyproject.toml:56,63`) | **no**: CUDA/ROCm on Linux only (`docs/install.md:7`, `docs/install_amd.md:9-11`). Its CPU side would run, since `setup.py:109-110` builds ggml-cpu `sandybridge`/`ivybridge` variants, but there is no GPU path | (a) a bandwidth-matched share of misses copied to the card (`moe/bench_profile.py:116-129`). (d) measure the expert union per verify window (`docs/performance/decode.md:232-235`) | Miss time goes from `bytes/c` down to at best `bytes/(p+c)`. Only the share `p/(p+c)` of the CPU miss time can move, with `p` = 11.1 and `c` unmeasured. Reduced by DRAM contention, because the copy also reads host RAM (`decode.md:75-78`) | medium: a new Metal upload plus compute path per layer, and per-layer sync. Results not byte-identical to the CPU path |
| **mesh-llm** (Skippy) | Dense models split into contiguous layer stages across machines over iroh/QUIC. Raw-f32 activation wire (`skippy/docs/SKIPPY_SPLITS.md:166-169`). Pipelined MTP+n-gram verify windows (`skippy/docs/PIPELINED_VERIFY_WINDOW.md:11-17`) | Rust, patched llama.cpp `620d2225` (`skippy/llama_cpp/upstream.txt`); prebuilt Metal for Apple Silicon only | **no** as shipped: `install.sh:206-209` marks only `Darwin/arm64`, Linux x86_64 and Linux aarch64 as supported, and `install.md:183` says "Intel macOS is not currently available through Homebrew". A source build on x86_64 Darwin is UNVERIFIED. Also only one machine is here | (c) pipelined speculative verify windows over the fork's layer split (two cards + host) | At batch 1 a layer split is sequential, so stages idle. Depth-d windows can keep up to d stages busy, minus stale work after a divergence. Bound: tokens/s ≤ 1 / max(stage time) x accepted per window. Unknown until stage times are measured | high: the speculative scheduler is rewritten; blocked by ticket 68 (zeros on a two-cards-plus-host split) |
| **Colibri** (the closest match to "Cabilary") | MoE experts streamed from disk by `pread` with per-layer LRU. A CUDA/Vulkan VRAM expert tier with heat-ordered warm start (`c/qwen36_tier.c:81`, `:1856-1875`) and per-conversation decay (`:29,34`). A **new** Metal backend (`c/backend_metal.mm`) | C + OpenMP. AVX2+FMA fast kernels (`c/qgemv.h:28,78`, `c/qwen36.c:1576`). `METAL=1` is macOS-only (`c/Makefile:686-697`). Vulkan via MoltenVK on macOS (`docs/vulkan.md:30`) | **partial.** CPU: fallback kernels only (receipts 10-21). Metal: "zero-copy over unified memory" (`backend_metal.mm:2`) wraps host pages in `MTLStorageModeShared` buffers (`:984-989`), so a D700 reads weights over PCIe. The 32-lane reductions disable themselves on 64-lane devices (`:1048-1068`). It picks the first non-low-power device (`:1015-1024`). Vulkan/MoltenVK on GCN 1.0: UNVERIFIED | (b) a persisted heat profile that warm-starts the arena in heat order, spread across layers (`qwen36_tier.c:1856-1875`) | Removes the cold start: the arena reaches its steady hit rate from token 1 instead of after N tokens. Steady-state decode: none | low: a file read at plan time. The fork already reads a prewarm key list for the *host* cache (`moe/0021` patch lines 2736-2745) |
| **AirLLM** | Dense layer-by-layer streaming from disk with a prefetch thread (`air_llm/airllm/airllm_base.py:66`, `:186`) and optional 4/8-bit shards via bitsandbytes (`:106-107`, `:131-133`) | darwin → MLX (`auto_model.py:7-11`); CUDA → MPS → CPU elsewhere (`utils.py:97-101`) | **no**, unchanged at the new HEAD: `auto_model.py:8,11` (MLX on darwin), `:31,69-72` (only Llama/Mistral on macOS) | none new. Layer streaming = mmap at `-ngl 0` | dense decode from disk ≤ NVMe rate / model bytes (NVMe unmeasured) | — |
| **Strata** | MoE: hot experts in an arena, the rest streamed from SSD with next-layer read-ahead. On ≥64 GB Macs the arena is wired with `mlock` (`docs/MAC.md:59-67`) | Apple Silicon M1+, macOS 15+ (`docs/INSTALL.md:25`); HIP/CUDA on PC | **no**, unchanged at the new HEAD: `docs/MAC.md:3-4` "Intel Macs cannot run it" | none new. Read-ahead is in `moe/0033`; a locked RAM cache is in `moe/0021` (patch line 3113) | — | — |
| **moe-l2** | A llama.cpp fork: experts in lazily mmapped host RAM, pinned on first use, read by the GPU **zero-copy over PCIe**, plus a VRAM LRU ("A3 cache"). A routing table by domain pre-pins hot experts (`README_zh.md` lines 138-139, 201, 62-65) | CUDA 12.8 prebuilt bins, sm_60 and up, AVX2 Windows build (`README_zh.md:70`) | **no**: CUDA only | (b) per-domain routing tables = the heat profile idea. Zero-copy GPU reads of host memory: see H2 (likely a loss here) | Zero-copy: the card can read host memory at no more than the PCIe rate. Here that is about 11 GB/s for a copy, and the zero-copy shader rate is unmeasured. The host CPU reads at 51.6 GB/s, so CPU compute of misses should win | measure only |
| **flash-moe** | Qwen3.5-397B-A17B from SSD: parallel `pread` of K=4 experts per layer with GCD, no custom cache ("trust the OS"), serial GPU→SSD→GPU pipeline (`README.md:36,52,55-67`) | Apple M3 Max, 48 GB unified, 17.5 GB/s SSD (`README.md:24-27`); one model only | **no**: Apple-Silicon Metal kernels, one hard-coded model | Its negative results apply: `mmap` of cold expert files "-5x" against `pread`, prefetch "net 0%" **because of unified memory** (`README.md:128,134`) | On this Mac the GPU has its own VRAM, so the unified-memory reason for serialising SSD reads and GPU work does not hold. Overlapped prefetch is not refuted here. The fork already uses `pread` (`moe/0021` patch lines 2454, 2697) | measure only |
| **prima.cpp** (arXiv 2504.08791) | Piped-ring parallelism: layer windows over a ring of devices, several rounds per token, each device prefetching its next window from disk through mmap. Halda ILP scheduler | CUDA, Metal and CPU per the paper (v2 HTML). Repo not reachable at the v1 URL; v2 lists Gitee | UNVERIFIED (no code read). Its target is several machines whose RAM+VRAM is below the model size | Multi-round windows to avoid "prefetch-release" eviction. Relevant only for a model over 64 GB on this box | bounded by NVMe rate / bytes per token (unmeasured) | — |
| **HOBBIT** (arXiv 2411.01433) | Loads a **lower-precision** copy of less important missed experts; layer-level prefetch; sequence-level cache; built on llama.cpp | edge devices (hardware UNVERIFIED from the abstract) | idea only | a lower-bit host copy of cold experts for CPU-computed misses | CPU miss time scales with bytes read, so a Q4_K copy of a Q6_K expert reads fewer bytes. Changes outputs, so it is a quality gate, not a speed gate | medium; doubles host RAM for the duplicated experts |
| **Fiddler** (arXiv 2402.07033, ICLR 2025) | compute missed experts on the CPU instead of copying them | hardware UNVERIFIED from the abstract | already in the fork (Dynamic MoE CPU misses) | — | — | — |
| **MoE-Lightning** (arXiv 2411.11217) | CGOPipe CPU-GPU-I/O pipeline with paged weights; roofline-model scheduler; **batch throughput** | single T4 16 GB, and 2-4 T4s (abstract) | idea only | none for batch-1 chat. Same regime objection as FlexGen in the 11-04 survey | — | — |
| **"FreeToken"** | = FreeToken above | | | | | |
| **"Cabilary"** | **not identified** (see §3.9) | | | | | |

## 3. Per project

### 3.1 FreeToken

Paper: "FreeToken: Efficient Edge-Native MoE Serving with Bandwidth-Adaptive Execution", Yang et al., arXiv 2608.16157,
v1 2026-08-17 (Berkeley/MIT/Stanford author list on the abstract page). The abstract names hardware tiers (8 GB
laptop GPU, gaming desktop, workstation GPU) but no exact devices. Per-device headline numbers such as "35B on an 8 GB
GPU at 39.3 tok/s" appear only in secondary coverage and are UNVERIFIED.

**Mechanism, from source.**
- **Strategies.** `python/freetoken/moe/__init__.py:3-9` defines `fused | offload | cpu | hybrid`. In the offload
  family, all experts sit in pinned host banks and the GPU holds a slot cache plus a two-layer prefill double buffer.
  `docs/models.md:46-58` documents the same set.
- **Miss cost.** `docs/performance/decode.md:31-34`: step ≈ `t_hit + misses × bytes/expert / PCIe`. The copy cannot
  hide behind compute, because "a layer knows its experts only after its router runs" (`:22-23`).
- **Hybrid split.** `bench_profile.fetch_fraction` (`moe/bench_profile.py:116-129`) returns
  `pcie_ov / (pcie_ov + cpu_ov)` from an *overlapped* measurement of both rates. `decode.md:53-60` derives it:
  misses then cost `bytes/(p+c)` at best instead of `bytes/p`. Rounding the share to an integer count per layer is
  `FREETOKEN_HYBRID_FETCH_ROUND` (`moe/offload_kernels.py:18-25`). The default `min-wait` makes a large cache never
  fill (`decode.md:126-131`).
- **Two costs of hybrid** (`decode.md:83-88`): CPU-computed experts are not cached, and every MoE layer pays a CPU
  round trip (6 µs, 0.25 ms per step on their machine).
- **CPU/GPU handshake.** It uses stream memory operations (`cuStreamWriteValue64`/`WaitValue64`), not host callbacks,
  because the callback path cost ~30-50 µs per call (`moe/cpu_executor.py:27-40`).
- **Cache floor.** The cache must hold at least one step's experts, `top_k/num_experts`. Below that every access
  misses (`decode.md:114-121`).
- **Speculative decoding on MoE.** "A verify step reads the union of the k + 1 tokens' experts". Four consecutive
  tokens touched 2.3-2.75x the experts of one token across four MoE models (`decode.md:232-235`). MTP gain drops from
  2.00x (fused) to 1.26x (offload, 20% cache) on the 35B-A3B (`decode.md:243-249`).
- **Prefill.** Each MoE layer copies all its experts per chunk. With overlap, chunk time ≈ max(copy, compute)
  (`docs/performance/prefill.md:15-33`).
- **Hardware for every number above:** one RTX PRO 6000 (PCIe 5.0), a 16-core Xeon with 8-channel DDR5,
  Qwen3.6-35B-A3B NVFP4, bs=1 (`decode.md:9-11`). They measured PCIe at ~50 GB/s and CPU-MoE at 147-174 GB/s
  (`decode.md:69-73`).

**Why it does not run.** Requirements are "Linux x86_64, NVIDIA GPU, driver r580+ (CUDA 13)" (`docs/install.md:7`),
and CUDA kernels are JIT-compiled with `nvcc` (`:18`). AMD is "experimental": ROCm 7.14 on RDNA3/4 only
(`docs/install_amd.md:3-12`). The README names RTX 30/40/50 only (`README.md:24`). Nothing covers macOS, Metal or GCN.

**What this machine changes in the mechanism.**
- Their CPU-to-PCIe ratio was 2.93x. Here `p` is measured at about 11.1 GB/s and `c` is at most 51.6 GB/s. The CPU
  is relatively stronger here, so `f = p/(p+c)` is small and the fetch share is small.
- Their own warning applies with more force: "on a dual-channel desktop the copy would take a large share of the
  CPU's bandwidth (not measured here)" (`decode.md:77-78`). This box has 4-channel DDR3, and the overlapped pair has
  never been measured.
- The fork already computes every miss on the CPU (Fiddler-style, pooled-budget ticket 07). So the open question is
  whether a non-zero `f` pays here, net of the per-layer Metal handshake. The fork already uses shared events for that
  handshake (`moe/0066`, `moe/0067`, `TOSH_DMOE_SPIN_US`).

### 3.2 mesh-llm (Skippy)

- **What it is.** It pools machines behind one OpenAI endpoint. Its "Skippy stage splits" load contiguous layer ranges
  on peers (`README.md:136-141`; `skippy/docs/SKIPPY_SPLITS.md:3-12`). Peers fetch only the GGUF fragments of their
  stage (`README.md:139-140`). Activations cross the network as raw f32; f16 and q8 wires "failed" and remain research
  (`SKIPPY_SPLITS.md:166-169`).
- **Its one quoted run.** 14.98 generated tok/s on a 4x96 GB CUDA node plus a 48 GB node over a ~5 ms QUIC path, with
  a lopsided 65/1 layer plan (`SKIPPY_SPLITS.md:171-179`). It is labelled "not a recommendation".
- **Pipelined verify windows.** `skippy/docs/PIPELINED_VERIFY_WINDOW.md:11-17,108-137`: native MTP plus n-gram
  candidate chunks are sent through the stages in FIFO order with a fixed pipeline depth (`verify_window_pipeline_depth`,
  default 2, `:204-206`). Later windows go stale at the first divergence. The document gives a measurement plan
  (`:221-233`) but **no measured result** (UNVERIFIED effect).
- **Why it does not run.** The installer's `platform_support_status` accepts `Darwin/arm64`, `Linux/aarch64` and
  `Linux/x86_64` only (`install.sh:206-209`). The Metal flavour maps to `Darwin/arm64` (`install.sh:290,307`), and
  `install.md:183` reads "Intel macOS is not currently available through Homebrew". Even built from source, it is a
  multi-machine system and this is one box.
- **What is portable.** The pipelined-window idea, applied to the fork's own in-process layer split. Card 0, card 1 and
  host are stages. At batch 1 they run one after another, so two stages are idle while the third works. Overlapping
  speculative windows is the only way a layer split keeps more than one stage busy at decode. It is blocked behind
  ticket 68.

### 3.3 Colibri (and why it is the best "Cabilary" candidate)

Changed since the 10-21 receipts (`e0db083` → `0a5504a`):
- It now has GPU tiers: CUDA, HIP, Vulkan, XDNA and Metal (`GPU_BACKENDS.md:18-20`; `c/backend_*.{cu,c,mm}`).
- **Metal backend.** It is labelled "Apple-GPU (Metal) backend ... zero-copy over unified memory"
  (`c/backend_metal.mm:1-2`). Host weights are wrapped with `newBufferWithBytesNoCopy` in `MTLResourceStorageModeShared`
  when 16 KiB-aligned (`:984-989`). On an Intel Mac with a discrete card, a shared buffer lives in system memory, so
  every GEMV would read weights across PCIe. It does handle Intel Macs:
  - device choice falls back to `MTLCopyAllDevices()` and the first non-low-power device, citing "Intel Macs whose GPU
    is not the system default" (`:1015-1024`);
  - its 32-lane SIMD reductions disable themselves when `threadExecutionWidth != 32` (`:1048-1068`). That is the
    D700's 64-lane case, and it degrades to serial paths. This is a correctness guard, not a GCN fast path.
- **Vulkan on macOS** goes through MoltenVK (`docs/vulkan.md:30`). Whether its shaders run on GCN 1.0 under MoltenVK
  is UNVERIFIED, and this machine has no Homebrew to supply it (receipts 10-21).
- **The VRAM tier policy** (`c/qwen36_tier.c`):
  - per-expert `heat`;
  - per-conversation counts halved every 1024 ticks (`:29,34`);
  - a `HEAT_FILE` table loaded at start (`:81`);
  - warm-start fill in heat order, or expert-by-expert *across* layers when no heat file exists. Their reason: filling
    whole layers in index order left the bus idle for 25 layers, and then a prompt chunk copied all 256 experts of
    each layer while it waited (`:1856-1875`).
- **Disk reads** are `pread`, with an `O_DIRECT` twin in the Kimi K3 engine (`c/kimi_k3.c:62,1868-1963`), and
  `posix_fadvise(DONTNEED)` after slice reads (`c/inkling.c:1113,1121`).
- **Their numbers**, for orientation only:
  - Qwen3.6-35B-A3B at 6.0 tok/s CPU and 9.9 with Vulkan on the iGPU of machine A, a Ryzen 7 PRO 8700GE with DDR5;
  - 30.0 with CUDA on machine C (`README.md:208,266`).
- **Portable here:** the heat-file warm start and the cross-layer fill order. The fork's host cache already accepts a
  prewarm key list from a file (`moe/0021` patch lines 2736-2745, `TOSH_DMOE_HOST_PREWARM`). A grep of `moe/*.patch`
  found no equivalent warm start for the **VRAM arena**. The arena's residency is LFU with lazy decay, starting empty
  (`moe/0020` patch line 5033 onward).

### 3.4 AirLLM (re-checked at the new HEAD)

The verdict is unchanged:
- `air_llm/airllm/auto_model.py:7-11`: darwin imports `AirLLMLlamaMlx`.
- `:31`: `MLX_ARCHITECTURES = {"LlamaForCausalLM", "MistralForCausalLM"}`.
- `:69-72`: everything else is refused on macOS.
- `utils.py:97-101`: CUDA, then MPS, then CPU.

New since 10-21: a generic `AirLLMBaseModel` for any standard `*ForCausalLM` (`auto_model.py:13-17`). It does not
reach macOS. The mechanism is still dense layer streaming with a prefetch thread (`airllm_base.py:66,186`).

### 3.5 Strata (re-checked at the new HEAD)

- Unchanged: `docs/MAC.md:3-4` "Intel Macs cannot run it", and `docs/INSTALL.md:25` "Intel Macs are not supported by
  the Mac package".
- The Mac streaming policy is now documented (`docs/MAC.md:59-67`): an arena of the most-used experts with
  next-layer read-ahead, filled in 1.5 GB steps, and wired with `mlock` on ≥64 GB Macs "so macOS does not compress it".
- The fork already reads disk experts a layer ahead (`moe/0033`) into a locked RAM cache (`moe/0021` patch line 3113).
  Nothing new to port.

### 3.6 moe-l2

A CUDA llama.cpp fork from the author yalun753:
- Experts are lazily mmapped in RAM and pinned on first activation. The GPU reads active experts "by PCIe DMA"
  directly, with a VRAM LRU (`README_zh.md` lines 138-139, 201).
- Routing tables by domain pre-pin hot experts and can be swapped at runtime with `POST /moe-set-domain`
  (`README_zh.md:62-65,70`).
- Prebuilt CUDA 12.8 binaries, sm_60 and up; the Windows build is AVX2 (`README_zh.md:70`).

Numbers are RTX 4090 / 2080 Ti / 5090 runs by the author (`README_zh.md:15-24,72-79`), not independently verified.
Nothing runs here.

The zero-copy read is the one mechanism worth checking against this machine's numbers. A shader reading host memory
over PCIe 3.0 is bounded by the link. The only link number measured here is the 11.0-11.25 GB/s blit. The host CPU
reads the same bytes at up to 51.6 GB/s. So zero-copy GPU compute of misses is expected to lose to CPU compute here,
which is the fork's present choice. This is a bound, and H2 measures it.

### 3.7 flash-moe

- **What it does.** Qwen3.5-397B-A17B, 4-bit experts at 209 GB on disk, at 4.36 tok/s. Measured on a MacBook Pro M3
  Max, 48 GB unified, internal SSD measured at 17.5 GB/s, macOS 26.2 (`README.md:13-27`).
- **Mechanism.** Parallel `pread` of the K=4 active experts per layer with GCD, and no custom cache: the OS page cache
  hit ~71% (`README.md:36,52`). A serial GPU→SSD→GPU pipeline, because "SSD DMA and GPU compute share the same memory
  controller" (`README.md:65-67`).
- **Results that matter here** (`README.md:124-138`):
  - `mmap` expert files: "-5x", from per-page fault overhead on cold data;
  - `F_RDADVISE` prefetch: "net 0%", because of unified memory;
  - MTP: "break-even", because "MoE I/O scales per-token".
- **On this Mac:**
  - The unified-memory reason for serialising does not apply: the D700 has its own VRAM. So "prefetch does not pay"
    is **not** evidence for this box.
  - The mmap-vs-pread result agrees with the fork's choice of `pread` (`moe/0021` patch lines 2454, 2697, 2819).
  - The fork has an `F_NOCACHE` switch (`TOSH_DMOE_HOST_NOCACHE`, `moe/0021` patch line 2572).

### 3.8 prima.cpp, HOBBIT, Fiddler, MoE-Lightning

- **prima.cpp** (arXiv 2504.08791v2):
  - piped-ring parallelism, with k = L/W rounds per token over a ring of devices, each prefetching its next window
    via mmap;
  - avoids "prefetch-release" eviction by reloading one small window per round;
  - evaluated on an M1 Mac, an i9 + RTX 3070 laptop, an i9 + RTX 2080 Ti desktop and a Kirin 9000 phone, 37 GiB in
    aggregate, smaller than a 70B Q4_K model.

  Code not read: the v1 GitHub URL returned "not found" on clone, and v2 lists a Gitee repository. On one box with
  64 GB it matters only for models over RAM.
- **HOBBIT** (arXiv 2411.01433): mixed-precision expert offloading on llama.cpp. Less important missed experts load
  as lower-precision copies. Hardware is not in the abstract (UNVERIFIED).
- **Fiddler** (arXiv 2402.07033): CPU computes missed experts. Its abstract reports 1.26x single-batch over its
  baselines, hardware not stated (UNVERIFIED). Already the fork's design.
- **MoE-Lightning** (arXiv 2411.11217): CGOPipe CPU-GPU-I/O pipelining with an HRM roofline scheduler, built for
  **batch throughput** on T4s. Not the batch-1 regime.
- **Not surveyed:** exo and distributed-llama. prima.cpp's paper compares against both, and both are multi-machine.

### 3.9 "Cabilary": not identified

Searched:
- web search "Cabilary LLM inference";
- web search "Cabilary OR Capillary github LLM ... expert streaming";
- GitHub repository search API for `cabilary` (0 results), `kabilary` (0), `capilary` (10 unrelated: tour and order
  services), `capillary llm` (1 result: an agent-memory DAG) and `calibri llm` (2 unrelated).

Closest candidates:
1. **Colibri / colibrì** (JustVugg). It is the one big-MoE-on-small-hardware project whose name is phonetically near
   (co-li-BRÌ → "Cabilary" is plausible as a dictation slip). Covered in §3.3.
2. "Capillary": no inference project found.

If the user meant something else, the receipts here cannot say what.

## 4. Candidate beta-8 hypotheses

Every gate carries the CLAUDE.md method line:
- engine and pinned commit: XeonLLM `llama-server`/`llama-bench` sha256, llama.cpp `d81235049` + N patches;
- model and quant, `-c`, `-b`/`-ub`, `-t`, card index;
- N and whether warmups were discarded.

Further rules for every gate:
- No percentage against a modelled figure.
- Each A/B first proves its switch takes effect (a log counter that is non-zero only when the switch is on).
- Configurations that cannot run are named next to the numbers.
- Safety: no model over a card's working set, no command buffer over ~100 ms.

**H1. Copy a bandwidth-matched share of Dynamic MoE misses to the card (FreeToken hybrid `f`).**
- **Step 0, measure the overlapped pair.** Measure `p_ov` and `c_ov` together:
  - `p_ov`: the 1 GiB host-to-card blit (`tools/metal-probe/hostcopy.swift`, card 1) running *while* the CPU expert
    threads compute;
  - `c_ov`: expert rows per second converted to GB/s, while the blit runs;
  - N=5 processes, first rep discarded.

  If `p_ov/(p_ov+c_ov)` rounds to zero experts per layer for the 35B's top-k, stop here.
- **Gate:**
  - Ornith-1.0-35B Q6_K, `--dynamic-moe on`, expert tier on card 1, `-c 32768`, `-t` = shipped;
  - 6 alternating servers with `f=0` and `f=f*`, 1 warmup + 3 measured 128-token greedy requests, BST prompt;
  - report decode tok/s with sd;
  - the control is a per-layer "fetched N" counter, which must be 0 with `f=0`;
  - top-1 agreement against `f=0` over 128 tokens (not byte equality: GPU and CPU sums differ).
- **Reject** if the difference is within 5x the noise floor (CLAUDE.md rule 3).

**H2. The zero-copy read rate: can a D700 read host memory faster than the CPU computes from it?** (moe-l2,
Colibri Metal, FreeToken zero-copy gather)
- A read-only shader over a ≥1 GiB `MTLStorageModeShared` buffer on card 1. It is a variant of
  `tools/metal-probe/readceiling.swift`, ≥1 s soak, command buffers ≤100 ms, N=5 processes.
- Report GB/s and sd, next to the 204.4-206.1 GB/s VRAM read and the 10.98-11.25 GB/s blit.
- If it is not above 51.6 GB/s, record "zero-copy expert compute ruled out on this box" and close.
- This is a measurement only, for a Mocca ticket; nothing was run for this research.

**H3. The expert union per verify window on the 35B (FreeToken `decode.md:232-235`).**
- Same 35B launch as H1, with `TOSH_DMOE_STATS=1`, at `--draft-max` k ∈ {1,2,4}.
- For each k, report the mean distinct experts per layer per verify batch, and the CPU-computed misses per verify.
- N=3 servers per k, 1 warmup discarded.
- Proof that k took effect: accepted/drafted in the log.
- This predicts whether the DFlash drafter on the idle card (beta7 ticket 01) can pay on the expert tier. Every extra
  expert in the union is a CPU miss at host rate.

**H4. Warm-start the VRAM arena from a persisted heat profile (Colibri `HEAT_FILE`, moe-l2 router maps).**
- Write the per-(layer, expert) decayed score at shutdown. At plan time, fill the arena in that order, spread across
  layers (`qwen36_tier.c:1856-1875`).
- **Gate:**
  - the 35B as in H1;
  - 6 alternating cold launches with the profile on and off;
  - report decode tok/s for tokens 1-128 and 129-512 separately, plus the arena hit rate from stats for both windows;
  - the control is a log line "arena warm-started: N experts from <file>", which must be absent when off.
- **Expected:** a gain only in the first window. No change in steady state is the pass condition for the second
  window.

**H5. GPU prefill of host-placed dense models with layer double-buffering (FreeToken `prefill.md:15-33` = op
offload).**
- Blocked by beta7 ticket 08: offloaded mat-mul computes garbage.
- Bound from the mechanism: per ubatch, the whole weight file crosses PCIe once, so prefill tok/s ≤
  `ub / (file bytes / 10.98 GB/s)` when copy-bound. Overlap needs two layers of staging on the card.
- **Gate:**
  - as beta7 ticket 03: 27B Q8_0 at `-ngl 0` with card 1 visible;
  - `llama-bench -p 2048 -n 0 -r 3`, `-ub {512,1024,2048}`, `-nopo 0/1`;
  - MTL split count non-zero only with offload on;
  - greedy text agreement over 64 tokens.

**H6. The NVMe rate and the read primitive, before any model over 64 GB.** (flash-moe, Colibri, prima.cpp)
- Cold reads with `F_NOCACHE` of 1-8 MB at random expert offsets, queue depth {1,4,8} (parallel `pread`), plus a
  sequential 1 GiB read, from a ≥64 GiB file. Purge the page cache between runs, or read beyond 64 GB of distinct
  data. N=5. Report GB/s and sd.
- The internal SSD's link generation is UNVERIFIED (not looked up). Until this is measured, no disk-tier decode
  estimate can be written: MoE decode from disk ≤ NVMe GB/s / cold expert bytes per token.

**H7. Pipelined verify windows across the layer split (mesh-llm `PIPELINED_VERIFY_WINDOW.md`).** Only after ticket 68.
- Step 0: per-stage decode time on the two-cards-plus-host split of the 27B Q6_K, from `TOSH_DMOE_TIMELINE` or the
  per-op log. N=4.
- If one stage dominates, the bound is that stage's service rate and the idea is not worth building.
- **Gate:**
  - depth {1,2,4};
  - report tok/s, plus stale windows and stale ms;
  - the control is depth 1, which must reproduce serial verification byte-identically.

**H8 (quality-gated, lowest priority). A lower-bit host copy of cold experts for CPU misses (HOBBIT).**
- Gate on quality first: top-1 agreement and the logprob difference against the Q6_K reference over a fixed prompt
  set, with a bound set by the measured spread between two CPU runs.
- Speed second: the 35B decode as H1.
- It costs host RAM for the duplicate experts, against the 64 GB budget.

## Configurations that cannot be run (as of these commits)

- FreeToken on any path: CUDA 13 / ROCm 7.14 on RDNA3/4, Linux only.
- mesh-llm: the installer refuses Darwin/x86_64; a source build is unverified; and there is no second machine.
- moe-l2: CUDA only.
- flash-moe: Apple Silicon and one model.
- AirLLM: MLX on darwin.
- Strata: Apple Silicon or HIP/CUDA.
- Colibri: no fast CPU kernels on AVX1 and no OpenMP without libomp (receipts 10-21). Its Metal path reads weights
  zero-copy over PCIe on a discrete card. Vulkan/MoltenVK on GCN 1.0 is unverified.
- prima.cpp: code not reachable at its v1 URL.

## Sources

- FreeToken: https://github.com/FlashML-org/FreeToken (commit above), https://arxiv.org/abs/2608.16157
- mesh-llm: https://github.com/Mesh-LLM/mesh-llm (commit above)
- Colibri: https://github.com/JustVugg/colibri (commit above)
- AirLLM: https://github.com/lyogavin/airllm; Strata: https://github.com/Niko1221/Strata
- moe-l2: https://github.com/yalun753/moe-l2; flash-moe: https://github.com/danveloper/flash-moe
- prima.cpp: https://arxiv.org/html/2504.08791v2
- HOBBIT https://arxiv.org/abs/2411.01433; Fiddler https://arxiv.org/abs/2402.07033; MoE-Lightning https://arxiv.org/abs/2411.11217
- Secondary, used only to locate repos and never as evidence: wavect.io FreeToken review, the Pi discussion #8016
  (for moe-l2), and the betterstack / quantumzeitgeist FreeToken coverage.
