# How many distinct experts does a k-token verify touch on the 35B?

Type: task
Status: resolved
Mode: AFK (orchestrator)

## Question

On Ornith-1.0-35B Q6_K, run real decode and draft-verify windows, and count the distinct experts
per layer selected over k = 1, 2, 4 and 8 consecutive tokens (research 02, H3). Use a router
dump, for example the fork's per-layer expert counters, or an eval callback on the
`ffn_moe_topk` tensors. Run on the host (`-ngl 0`), so card 1's state does not matter.

The ratio distinct(k) / distinct(1), against the measured host verify curve t(k)/t(1) (beta7
ticket 04: 1.42, 2.16 and 5.91 for k = 2, 4, 8), says whether the 35B's verify cost is set by
expert reads. That decides whether any drafter can pay on the expert tier.

## Answer

Method:
- `tools/expert-count/expert_count.cpp`, linked against the dev `build-static` libraries
  (`d81235049` + series), `n_gpu_layers = 0`.
- An eval callback reads every `ffn_moe_topk-<layer>` tensor. It is a strided view of the argsort
  over all 256 experts, so it is read row by row; the first version read it contiguously and gave
  a meaningless 8/16/32/64.
- Ornith-1.0-35B Q6_K, a 90-token English prompt, windows of 8 consecutive tokens, 11 windows x
  40 MoE layers = 440 samples per k.
- Distinct experts are counted over tokens 0..k-1 of each window.

| k | distinct experts per layer, mean (min-max) | ratio to k=1 | host time t(k)/t(1) (beta7 04) |
|---|---|---|---|
| 1 | 8.00 (8-8) | 1.000 | 1 |
| 2 | 13.41 (9-16) | 1.676 | 1.42 |
| 4 | 21.21 (13-32) | 2.651 | 2.16 |
| 8 | 32.35 (18-61) | 4.044 | 5.91 |

**Reading.**
- Up to k=4, host verify time grows more slowly than the expert bytes. The attention and shared
  weights are read once per batch, so expert bytes are not all of the cost.
- At k=8, time grows faster than the experts (5.91 against 4.04), so something else switches on,
  such as another matmul path at batch 8. That is not measured; a ticket for the schedule.
- These are prompt tokens, not drafted continuations. Drafted tokens are likely more alike, so
  fewer distinct experts; UNVERIFIED.
- **For drafting on the host:** three drafted tokens (k=4) cost 2.16 x one token. At the DFlash
  acceptance seen (about 2.3 of 3 accepted, beta7 01) a round yields about 3.3 tokens, so host
  verification alone can pay.
- **The expert tier's failure to pay (beta7 01) must then come from the card half or the draft
  cost,** not the CPU experts. The card's verify curve is unmeasured: ticket 09 adds it.

Output: `evidence/08-expert-count-35b.txt`.
