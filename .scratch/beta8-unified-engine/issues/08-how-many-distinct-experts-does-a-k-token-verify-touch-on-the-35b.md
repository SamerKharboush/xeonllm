# How many distinct experts does a k-token verify touch on the 35B?

Type: task
Status: open
Mode: AFK (orchestrator)

## Question

On Ornith-1.0-35B Q6_K, run real decode and draft-verify windows, and count the distinct experts
per layer selected over k = 1, 2, 4 and 8 consecutive tokens (research 02, H3). Use a router
dump, for example the fork's per-layer expert counters, or an eval callback on the
`ffn_moe_topk` tensors. Run on the host (`-ngl 0`), so card 1's state does not matter.

The ratio distinct(k) / distinct(1), against the measured host verify curve t(k)/t(1) (beta7
ticket 04: 1.42, 2.16 and 5.91 for k = 2, 4, 8), says whether the 35B's verify cost is set by
expert reads. That decides whether any drafter can pay on the expert tier.
