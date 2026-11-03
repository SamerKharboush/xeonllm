# Engine survey, 2026-11-02: what newer engines do that fits a D700 pair and an AVX1 Xeon

Follows `third-party-receipts-2026-10-21.md` (Strata, AirLLM, Colibri: verdicts unchanged). Asked
for in the beta.6 round: "use all RAM + VRAM of the two GPUs and every core as one unit, load as
large a model as possible with layer and tensor splits". Sources are web searches and one fetched
README on this date; nothing below was built or measured here unless it says so.

## The hardware floor that filters everything

GCN 1.0 (no HIP, no ROCm on macOS, Metal only), PCIe with no peer link between the cards, AVX
without AVX2/FMA, 64 GB DDR3. Any engine whose CPU kernels need AVX2/FMA, or whose GPU path is
CUDA/HIP/MLX, cannot run here.

| engine | what it adds | runs here? | receipt |
|---|---|---|---|
| ik_llama.cpp (and forks) | fused MoE FFN, tensor overrides with op offload of RAM-resident tensors, a "graph" multi-GPU split mode, auto-fit of offloaded tensors to VRAM with per-GPU margins | no: CPU kernels need AVX2 + FMA3; GPU work is CUDA | fork READMEs (RodriMora, fenril22, NHClimber87 mirrors of ikawrakow/ik_llama.cpp) |
| KTransformers 0.5.3 | CPU/GPU hybrid MoE; new AVX2-only kernels (March/April 2026) besides AMX/AVX-512 | no: floor is AVX2, GPU side is CUDA | phoronix.com/news/KTransformers-0.5.3; github.com/kvcache-ai/ktransformers |
| cafe-llama.cpp | `-hmoe` experts in pinned host memory with a hot-expert VRAM cache, `-ssd` expert streaming from SSD by mmap, `--pipeline-parallel` overlap of host-to-device copies, turbo2/3/4 KV, EAGLE-4 and MTP drafts, safetensors loading | the CPU/mmap parts in principle; `-hmoe` and the measured numbers are CUDA (RTX 3090) | github.com/quimmedes/cafe-llama.cpp/wiki |
| upstream llama.cpp `--fit` | sizes context, layers and expert placement to free device memory, per-device margin list | **yes: already in our pinned engine** | `vendor/llama.cpp/common/arg.cpp:2891` (`--fit`), `:2935` (`-fitt MiB0,MiB1,...`), `:2960` (`-fitc`); `common/common.h:488-491` (min ctx 4096, 1024 MiB default margin); upstream issue ggml-org/llama.cpp#18390 (per-device margins) |

## What to take

1. **Let the engine fit memory instead of forcing `-ngl 99`.** The app passes `-ngl 99`, and the
   engine then logs `common_fit_params: not fitting params to free device memory: n_gpu_layers
   already set by user to 99, abort`. That is the root of the beta.6 14B failure: 9 GB of weights
   plus a 32k f16 KV on two 6.44 GB cards, about 6.9 GB per card, pages until the GPU watchdog
   fires. The fit already exists, with per-card margins. Open questions before the app uses it:
   does "free memory" on a D700 read `recommendedMaxWorkingSetSize` or something larger; does it
   prefer shrinking context over moving layers to the CPU (the ticket 67 rule says a partial
   offload of a dense model is slow here); does it compose with `--split-mode tensor`. Ticket to
   open; not in beta.6.
2. **Overlap host-to-device copies with compute** (cafe's `--pipeline-parallel`). It applies to
   the expert tier (`-cmoe`/`--n-cpu-moe`), where the scheduler copies expert weights. Our
   ticket 66 hybrid path is where it would land; it needs that path to be correct first.
3. **SSD expert streaming** is AirLLM's idea done per expert. On this box mmap at `-ngl 0`
   already pages experts from disk; a model over 64 GB is the only case it would change, which
   the plan's Phase 2.5 measures rather than ports.
4. **Turbo KV types** are already in the app (`Sources/Servers/Server.swift:337`,
   `turbo4`, `turbo3`). Nothing new.

## Not an option

"RAM and VRAM as one unified unit" does not exist on this hardware: the cards reach host memory
over PCIe at a small fraction of their own bandwidth, and they cannot see each other (no peer
group, ticket 54). Every engine above does the same thing under different names: decide which
tensors live where, then move as little as possible per token. The placement rule (ticket 67),
the expert tier, and `--fit` are our versions of that decision.
