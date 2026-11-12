# 15: quantised KV on the cards' flash attention
Type: measurement (orchestrator) · Status: done (no change: f16 stays the card default)
-ctk q8_0 -ctv q4_0 (and q8_0/q8_0) vs f16 on a card: decode/prefill at 8k context, text vs f16.

## Result (2026-11-12, Mocca; orchestrator re-ran one cell)

FA stays on with q8_0/q8_0 and q8_0/q4_0 KV (kernels `..._kq8_0_vq8_0_w64` / `..._kq8_0_vq4_0_w64`);
test-backend-ops FLASH_ATTN_EXT on card 1: 1993/1993 OK, hsk=128 quantised pairs 23/23 OK.
4B at -c 8192: KV 1152 MiB (f16) -> 612 (q8q8) -> 468 (q8q4). Text diverges from f16 at char 700 / 597.
Speed: f16 higher in every row of both models (pp and tg, d0/2048/6144). 4B tg128 d6144: f16 12.13,
q8q8 10.52, q8q4 10.42 tok/s. Orchestrator re-run (same engine, -r 1): f16 12.12, q8q8 10.52.
Decision: no app default change. Quantised KV is a memory option only (costs decode speed on the cards).
Evidence: `evidence/15/RESULT.md`.
