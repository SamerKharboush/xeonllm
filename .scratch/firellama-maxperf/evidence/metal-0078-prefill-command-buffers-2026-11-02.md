# metal/0078: prefill graphs on a discrete card use shorter command buffers (2026-11-02)

## The failure it fixes

Qwen3-14B-Q4_K_M, `GGML_METAL_DEVICE_LIST=0,1`, `--split-mode layer`, `-ngl 99`, `-c 32768`,
f16 KV, default `-ub 512` (the app's launch). Each card holds about 6.9 GB (MTL0: 3954 MiB
weights + ~2688 MiB KV + 284 MiB compute) against a 6.44 GB `recommendedMaxWorkingSetSize`, so
the driver pages. On a ~5.4k-token prompt the second of the graph's two command buffers ran past
the GPU watchdog:

    ggml_metal_synchronize: error: command buffer 0 failed with status 5
    error: Caused GPU Timeout Error (00000002:kIOAccelCommandBufferCallbackErrorTimeout)

and the backend failed every later request with HTTP 500 "Compute error.". `-ub 256` or
`-c 8192` passed; `TOSH_N_MAIN_FIXED=1` did not help; tensor split (many short buffers per
graph) passed at about 7.1 GB per card.

## The change

A graph whose first matrix product carries >= 32 tokens is encoded into
`TOSH_MTL_PREFILL_CB` + 1 command buffers (default 4 + 1) on a device without unified memory
and with no abort callback. Every other graph keeps `n_cb` as `ggml_metal_set_n_cb` set it (1).
`ggml_metal_adapt_n_main` reads the main buffer of the graph it measured (`n_cb_last`) and skips
a graph whose layout changed; `ggml_metal_synchronize` checks every slot. The overcommit itself
is not fixed: see the placement-rule follow-up (the rule checks weights only, not KV).

## Gates (dev tree build-static, pin d81235049, llama-bench sha256 prefix eaeaac2a)

| gate | result |
|---|---|
| G1 build | llama-server, llama-bench, test-backend-ops build |
| G2 series | `check-patch-series.sh d81235049...`: 88 of 88 apply cleanly, 0 fail |
| G3 ops | card 0 and card 1: MUL_MAT 1832/1832, MUL_MAT_ID 936/936, FLASH_ATTN_EXT (TOSH_FA_AMD=1) 1993/1993 |
| G4 repro | default: `200 334.2 s`, timeouts=0. Control `TOSH_MTL_PREFILL_CB=1`: `500 218.3 s "Compute error."`, timeouts=2 |
| G7 text | Qwen3-4B-Q4_K_M card 1, 1639-token prompt, 128 tokens greedy: byte-identical default vs control; `-lv 4` log: `MTL0: batch graphs use 5 command buffers (TOSH_MTL_PREFILL_CB=4)` (the control prints none) |

G5/G6, throughput, default against the control (method: llama-bench above, FA on,
`TOSH_FA_AMD=1`, -b 2048 -ub 512, warmup run discarded by llama-bench; card 1 alone unless
noted):

| cell | N | default t/s (sd) | `TOSH_MTL_PREFILL_CB=1` t/s (sd) |
|---|---|---|---|
| Qwen3-4B Q4_K_M tg128 | 5 | 16.716 (0.003) | 16.718 (0.005) |
| Qwen3-4B Q4_K_M pp512 | 3 | 82.459 (0.003) | 82.493 (0.008) |
| Qwen3-4B Q4_K_M pp2048 | 3 | 67.851 (0.013) | 67.196 (0.221) |
| Qwen3-14B Q4_K_M pp2048 d0, both cards layer, default ctx | 1 | 29.433 | 29.355 |
| Qwen3-14B Q4_K_M pp2048 d4096, both cards layer, default ctx | 1 | 20.351 | 20.335 |

tg128 is unchanged within the noise (shipped beta.6 engine reference: 16.721, sd 0.004). pp512
reads 0.034 t/s lower with the patch, about four times the larger sd; pp2048 reads 0.65 higher,
three times the control's sd. Both are under 1% and N=3; we read them as no cost to prefill, not
as a gain. The 14B rows are N=1 at llama-bench's small context, where the cards are not
overcommitted, so they say nothing about the watchdog case.

## Implementer note

The first attempt (delegated) produced a file that was not a valid diff, called a function
before its definition, overwrote `n_cb` for good after the first prefill graph and logged a
WARN per graph; no gate ran. It was discarded and the patch written by the orchestrator.
