# 21: decomposed prefill for head 64/128 on 64-lane cards (keep FA for decode)

Type: task (Mocca code + measurement, orchestrator gates) · Status: done (metal/0083) · From: ticket 19

`src/llama-graph.cpp` `amd_prefill_fa_blocked` keeps the blocked FA kernel for prompt batches of head
64/128 models on 32- and 64-lane cards. On the D700 (64 lanes) the decomposed path reads prompts much
faster at depth and decode is unchanged (ticket 19 + `evidence/19/orchestrator-check.txt`). Change the
default on simd width 64 only (32-lane cards keep today's rule); keep an env switch to restore the block.
Gate: text identical; test-backend-ops unaffected (graph change only); pp512/tg128 at depth 0/2048/6144,
ub 128 and ub 512, 0.6B and 4B, new default vs restored block, two processes each, card 1.

## Result (2026-11-12, Mocca; orchestrator re-ran one cell)

Patch `patches/llama/metal/0083-metal-fa-prefill-block-is-off-on-64-lane-cards.patch`; series 93/93 clean on d81235049.
Every pp512 row of all four groups (0.6B/4B x ub 128/512, depth 0/2048/6144) is "new higher"; decode rows
not resolved or noise-level. 4B ub128 pp512 new 92.9/76.5/56.1 vs old 88.0/51.9/27.6 tok/s; text byte-identical.
Orchestrator check, same engine, card 1, 4B ub128 d6144 pp512 -r 1: new 56.39, `TOSH_FA_PF_W64=1` 27.61.
Evidence: `evidence/21/RESULT.md`. Note: TOSH_FA_AMD is not read anywhere in the engine source at this
series (Mocca's grep; confirmed by orchestrator in ggml/ and src/) — the app's setting is inert.
