# 16: a dense model across both cards and RAM answers zeros (ticket 68, beta7 06)
Type: bug (orchestrator) · Status: done (metal/0084)
See beta7 ticket 06. Bisect fusions by environment, then the mixed-placement path.

## Result (2026-11-12, Mocca; orchestrator re-ran both sides)
Cause: the fused gated-delta-net state gather/copy (`ggml_metal_gdn_state_fusion_on`) is wrong whenever the
graph is split over more than one Metal device (zeros on twocard12/two24/two28, 4-5 runs each; the switch alone
fixes it; control with every other fusion off still zeros). Root cause inside the fused path still open
(hypothesis: it reads the layer's recurrent cache buffer from the wrong card).
Fix metal/0084: fusion off when the Metal backend registered >1 device, `TOSH_GDN_STATE_FUSION_MULTI=1` keeps it on.
twocard12/two24 text identical to one12; MULTI=1 gives zeros again; one card keeps `rows=1_fold=1`. otool 0.
The app sets GGML_METAL_DEVICE_LIST/DEVICES only when it splits across cards, so one-card launches keep the fusion.
Note: GPU text differs from the host-only text at char 178 (also on one card): GPU-vs-CPU class, not this bug.
Evidence: evidence/16/RESULT.md, evidence/16/fix/RESULT.md.
