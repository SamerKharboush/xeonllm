# Re-measure the card-1 results of 2026-11-04 on card 0

Type: task
Status: open
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

Card 0 drives the display: keep every command buffer short and every model under its working set.
Record whether the display was awake.
