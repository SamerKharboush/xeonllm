# How fast can a D700 read host memory directly, and how fast is the NVMe?

Type: task
Status: open
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
