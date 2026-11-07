# Re-measure the card-1 results of 2026-11-04 on card 0

Type: task
Status: resolved (the two cards agree on decode and verify; offload text right on both; LFM3 right on both)
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

## Steps 3-6 (2026-11-07, after the second cold power cycle)

Card 1 passed `test-backend-ops` 13983/13983 first (`evidence/09/c1-after-cycle2-all.log`). No gpuRestart
during any run below (newest stays `Kernel_2026-11-06-195514`). Script `evidence/09/engine2.sh`, log
`engine2.log`. Method: dist llama-bench sha256 `82725c7682afbab9` (d81235049 + series, AVX1),
`GGML_METAL_DEVICE_INDEX=0|1 TOSH_FA_AMD=1`, `-ngl 99 -fa 1 -r 5`, cards alternating per model,
llama-bench's own warmup discarded, default ctx/batch (2048/512), display awake, user's CPU-only
llama-server on :8080 idle-resident.

**Step 3, decode `-p 0 -n 128` (tok/s, mean ± sd of 5):**

| model | card 0 | card 1 | weight bytes x tok/s (GB/s, not a measured read rate) |
|---|---|---|---|
| Qwen3-0.6B Q8_0 | 56.74 ± 0.38 | 57.56 ± 0.28 | 36 |
| Qwen3-4B Q4_K_M | 16.39 ± 0.02 | 16.64 ± 0.01 | 41 |
| Qwen3-4B Q6_K | 13.867 ± 0.006 | 13.869 ± 0.005 | 46 |
| Qwen3-8B Q4_K_M | 10.222 ± 0.002 | 10.223 ± 0.002 | 51 |

The 4B Q6_K and 8B cells agree within noise; the 0.6B and 4B Q4_K_M card-0 cells sit 0.25-0.8 tok/s
below card 1, outside the sd (N=1 process per cell; card 0 also drives the display). The 11-04 card-1
decode figures (37-52 GB/s by the same weight-bytes proxy) are reproduced on both cards: card 1's
fault that day did not show in decode rate.

**Step 6, verify curve `-p 1,2,4,8 -n 0` (time per verify = k / t/s, ms):**

| model | card | k=1 | k=2 | k=4 | k=8 |
|---|---|---|---|---|---|
| 4B Q4_K_M | 0 | 59.4 | 112.7 | 147.8 | 245.3 |
| 4B Q4_K_M | 1 | 59.5 | 112.6 | 148.2 | 245.4 |
| 8B Q4_K_M | 0 | 97.8 | 174.5 | 216.6 | 395.1 |
| 8B Q4_K_M | 1 | 98.0 | 174.4 | 216.6 | 393.8 |

The two cards agree within 1 ms at every k. On a card t(2)/t(1) is 1.90 (4B) and 1.78 (8B), against
1.42-1.47 on the host: verifying 2 drafted tokens on a card costs nearly two single tokens, so a
drafter feeding a card-placed target needs a higher acceptance than the host numbers in ticket 03
suggested. k=4 is the efficient point on both models (t(4)/t(1) 2.49 and 2.21).

**Step 4, op offload:** done in beta7 ticket 08 (2026-11-07) on both cards: with the scheduler fix
the text at `-ngl 0` is byte-identical with offload on and off for 0.6B, 4B and gemma4 12B, and the
prompt MUL_MATs are shown on the card. Beta7 ticket 08 was card 1's fault state, as far as anything
can be named. The prefill A/B is beta7 ticket 03's re-run.

**Step 5, LFM3-1.7B F16 `-ngl 99`:** card 0 and card 1 both answer "The capital of France is Paris.",
reasoning plus answer byte-identical to the host. Gate cell (build-static, 0079+0080, sha256
`76d8a41a80b30c1a`), `-p 512 -n 128 -r 5 -fa 1`: card 0 pp512 230.44 ± 0.23, tg128 23.010 ± 0.023;
card 1 pp512 230.28 ± 0.44, tg128 23.025 ± 0.012 tok/s.
