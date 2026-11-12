# 21: decomposed prefill for head 64/128 on 64-lane cards (keep FA for decode)

Type: task (Mocca code + measurement, orchestrator gates) · Status: ready · From: ticket 19

`src/llama-graph.cpp` `amd_prefill_fa_blocked` keeps the blocked FA kernel for prompt batches of head
64/128 models on 32- and 64-lane cards. On the D700 (64 lanes) the decomposed path reads prompts much
faster at depth and decode is unchanged (ticket 19 + `evidence/19/orchestrator-check.txt`). Change the
default on simd width 64 only (32-lane cards keep today's rule); keep an env switch to restore the block.
Gate: text identical; test-backend-ops unaffected (graph change only); pp512/tg128 at depth 0/2048/6144,
ub 128 and ub 512, 0.6B and 4B, new default vs restored block, two processes each, card 1.
