# How fast can a D700 read host memory directly, and how fast is the NVMe?

Type: task
Status: resolved
Mode: AFK (orchestrator: it runs GPU programs)
Blocked by: 01

## Question

Two rates decide the zero-copy and streaming ideas (research 02, H2 and H6).

1. **A D700 reading a shared (host) buffer directly.** Use the read-ceiling kernel
   (`tools/metal-probe/readceiling.swift`) over a `.storageModeShared` buffer:
   - at least 1 GiB, one pass per command buffer, the soak and the bounds from that probe;
   - on a card that passes ticket 01 (card 0 if card 1 does not);
   - N = 5 processes.

   At or below the host's 51.6 GB/s, zero-copy expert reads are out.
2. **The internal SSD's sequential and 2 MiB-block random read rate,** uncached (`F_NOCACHE`), on a
   file larger than RAM if possible (the 28.5 GB 35B Q6_K), N = 5.

The answer records both rates with method lines.

## Answer (2026-11-05)

### 1. A D700 reading host memory directly: 4.2-6.9 GB/s, and it wedged card 1

Method:
- `tools/metal-probe/readceiling.swift` with its new `shared` mode: a `.storageModeShared` 1 GiB
  buffer, filled by the host. Each command buffer reads one 128 MiB slice, so a pass takes about 20 ms.
- Soak of at least 1.5 s per variant, one warmup pass discarded.
- Both cards, alternating with the private read and the host copy (`evidence/09/probes.sh`).
- Display awake; RustDesk was capturing the screen (about 55% of one core).

| card | rep | `read4` 1024x256 | `read4` 4096x256 | `read4` 512x64 | `read1` 1024x256 | `read1` 4096x256 |
|---|---|---|---|---|---|---|
| 0 | 1 | 4.89 | 5.25 | 4.24 | 4.95 | 5.34 |
| 0 | 2 | 4.77 | 5.40 | 4.51 | 4.94 | 5.38 |
| 1 | 1 | 5.67 | 6.16 | 6.91 | 5.63 | 6.19 |
| 1 | 2 | (hung, see below) | | | | |

GB/s = 1e9 bytes/s. N = 3 processes completed, not the 5 planned.

**Zero-copy expert reads are out.** These rates are below the host's own 51.6 GB/s by about an
order of magnitude. They are also below the blit copy into the card (10.9-11.5 GB/s, same runs).

**Hazard.** Card 1's second shared-read process, started at about 15:16, never got its first
command buffer back:
- `waitUntilCompleted` did not return, and the process sat for 34 minutes;
- the driver reset card 1 (PCIe [2:0:0], Slot-1, the headless card, Metal device 1) at 15:16, 15:23,
  15:32, 15:36 and 15:43, then again at 15:52 when I killed the process and at 15:56;
- afterwards card 1 could not finish the first kernel of `test-backend-ops -o ADD` (120 s alarm, 3 ops,
  `evidence/09/c1-after-resets-*.log`).

The 11-04 fault began the same way: a run of resets on [2:0:0]. Rule: never point a D700 kernel at a
shared (host) buffer for bulk reads. The engine does not: it logs `use shared buffers = false` on these
cards.

### 2. The internal SSD (APPLE SSD SM1024G, PCIe AHCI)

Method:
- `tools/storage-probe/nvmeread.c`: `F_NOCACHE`, sequential 8 MiB `pread`s over 4 GiB, then 1000
  random 2 MiB-aligned 2 MiB blocks outside that range.
- Page-cache residency is checked (`mincore`) before each phase. N = 5 processes, each on a different
  4 GiB region.
- File: Nanbeige4.3-33B Q8_0, 35.2 GB, 0.0000 resident before every phase and still 0 after.
- No model here is larger than the 64 GB of RAM.

| rep | sequential GB/s | random 2 MiB GB/s | ms per block |
|---|---|---|---|
| 1 | 1.479 | 1.246 | 1.68 |
| 2 | 1.479 | 1.257 | 1.67 |
| 3 | 1.462 | 1.261 | 1.66 |
| 4 | 1.474 | 1.262 | 1.66 |
| 5 | 1.474 | 1.263 | 1.66 |

**Sequential 1.46-1.48 GB/s, random 2 MiB 1.25-1.26 GB/s.**

A first attempt on the 35B Q6_K reported 6.8 GB/s. That file was 85-100% in the page cache, so
those runs measured RAM, not the SSD; they are kept as `evidence/09/nvme-cached-35b.log` and are not
a result.

Weights streamed from this SSD arrive at about 1/35 of the host RAM read rate. Streaming a model
larger than RAM (AirLLM, "LLM in a flash") would be bound near 1.5 GB/s of weights per token step.
