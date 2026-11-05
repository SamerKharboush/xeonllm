# Re-measure the card-1 results of 2026-11-04 on card 0

Type: task
Status: open (steps 1-2 done; 3-6 wait for a cold power cycle)
Mode: AFK (orchestrator: it runs GPU programs)

## Question

Card 1 failed `test-backend-ops` (ADD 51/82, MUL 43/73, RMS_NORM 29/51, SSM_CONV 2/45) on
2026-11-04, the same day these were measured on it. Card 0 passed every op that day. On card 0,
what do these give?

1. The read ceiling (`tools/metal-probe/readceiling.swift`, 1 GiB, one pass per command buffer).
2. The host-to-card copy rate (`tools/metal-probe/hostcopy.swift`).
3. Decode `llama-bench -p 0 -n 128 -r 5 -fa 1` for Qwen3-0.6B Q8_0, 4B Q4_K_M, 4B Q6_K, 8B Q4_K_M.
4. **Op offload with the scheduler fix** (`.scratch/beta7-unified-performance/evidence/03/ggml-backend.with-sched-fix.cpp`):
   - does Qwen3-0.6B / 4B / gemma4 12B text at `-ngl 0` come out right on card 0?
   - If yes, beta7 ticket 08 was card 1, and the prefill gain (host 10-12 against offload 21-22
     tok/s on gemma4 12B) is real.
5. **LFM3-1.7B F16 at `-ngl 99` on card 0:** does it answer "Paris" like the host does?

6. The card verify curve: `llama-bench -ngl 99 -p 1,2,4,8 -n 0 -r 5` for the 8B and the 4B on card 0 (from ticket 08: the expert tier's drafter loss must come from the card half).

Card 0 drives the display: keep every command buffer short and every model under its working set.
Record whether the display was awake.

## Progress (2026-11-05)

Steps 1-2 measured on both cards (`evidence/09/probes.log`, the same probe binaries rebuilt from
`tools/metal-probe/`; 1 GiB private buffer; one pass per command buffer; at least 1.5 s soak; warmup
discarded).

| card | rep | `read4` 1024x256 | `read4` 4096x256 | `read4` 512x64 | `read1` 1024x256 | `read1` 4096x256 | host copy (GPU-time GB/s) |
|---|---|---|---|---|---|---|---|
| 0 | 1 | 141.78 | 139.46 | 171.70 | 184.61 | 194.66 | 11.35-11.45 |
| 0 | 2 | 195.53 | 198.72 | 197.31 | 184.16 | 194.65 | 11.32-11.42 |
| 1 | 1 | 205.69 | 206.40 | 204.31 | 191.12 | 201.85 | 11.39-11.53 |
| 1 | 2 | 205.70 | 206.51 | 204.45 | 191.24 | 201.85 | (not reached) |

- Card 1's read ceiling (204.3-206.5) and host copy (11.4-11.5) match its 11-04 values
  (204.4-206.1 and 11.4-11.6). Those two 11-04 numbers stand, even though the card was faulty then.
- Card 0 is the display card. Its first process read 139-172 with `read4`, its second 195-199.
  These are two observations, not one rate; the first process may have shared the card with the
  display. Card 0 sits below card 1 in both processes.

**Stopped.** The shared-buffer read of ticket 07 wedged card 1 (7 resets on [2:0:0]; see ticket 07).
Steps 3-6 (decode, op offload text check, LFM3 on a card, verify curve) wait for a cold power cycle.
Scripts ready: `evidence/09/engine.sh`, `evidence/09/offload.sh` (it swaps the scheduler fix into the
vendor tree, rebuilds, and restores the file; the vendor copy is saved as
`evidence/09/ggml-backend.vendor.cpp`).
