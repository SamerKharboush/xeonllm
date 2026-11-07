# Which unified schedule does beta 8 build?

Type: grilling
Status: resolved (2026-11-07, grilled with the user)
Blocked by: 01, 07, 08, 09

## Question

Given card 1's health, the research and the beta 7 measurements (the card reads ~205 GB/s while
decode moves 37-52 GB/s; host prefill 10-12 tok/s; offload faster but computing garbage; the
drafter on the idle card does not pay), which placement and schedule does beta 8 build, per model
class? And in what order do the enabling fixes land (ticket 68, beta7 08, beta7 07)?

## Answer (2026-11-07, every recommendation accepted by the user)

1. **Beta.7 ships first**, from what is verified: 0079 (LFM3), 0080 (AVX1 expert dots), the launch card
   check (f512e24). No placement change in beta.7; the scheduler fix stays out.
2. **Placement per model class in beta 8:**
   - dense that fits one card (up to ~5.5 GB): all layers on one healthy card (unchanged);
   - dense 5.9-11.8 GB: layer split across both cards (unchanged);
   - dense over both cards (gemma4 12B Q8_0, 27B): weights on the host, **prompt batches offloaded to
     one healthy card** (measured 12.9 -> 21.3 tok/s pp512 on the 12B, text byte-identical; beta7 03/08);
     layers-on-cards-plus-host stays out until ticket 68 (beta7 06) is fixed and measured;
   - MoE over the cards (35B-A3B): host path; prompt offload of MUL_MAT_ID only if a gate run on the
     35B shows the same text and a higher pp.
3. **Drafts sized to the verify curve:** cap n-gram and MTP drafts at 4 on a card and 3 on the host,
   each cap kept only if its A/B beats the noise. The drafter on the idle card stays dropped (beta7 01).
4. **Keep the pin** `d81235049` for beta 8 and backport; a bump is a later effort.
5. **How offload ships:** an engine patch (the scheduler fix + a guard that turns offload off, with a
   log line, when the card's compute buffer would exceed 1.5 GB, decided before allocating); the app
   names one healthy card for a host-placed model (card 1, the headless one, first; card 0 if the
   launch check left card 1 out); a test that an excluded card is never named.
6. **Order:** offload (engine, then app) -> the 35B MoE offload gate -> draft caps A/B -> ticket 68
   (orchestrator: big models on the GPUs) -> ticket 07 (per-op decode profile first, then a
   load-shape kernel).
7. **llama-modchip** (synchopate, Apache-2.0, AVX-512/AVX2 + Vulkan/CUDA, no Metal-on-AMD, no
   multi-GPU): carry over ideas, not code: (i) its n-gram predictor idea for drafting, gated with the
   caps; (ii) non-temporal prefetch in the AVX1 dot kernels for host decode, gated on the 35B;
   (iii) measure q8_0/q4_0 KV on the cards' flash attention. Not taken: Q2_0 "Fractal-64" (no AVX1 or
   Metal kernel, needs requantised models). Lossy options (expert top-k, attention window/sinks)
   are beta 9+ opt-in research behind a perplexity gate.
