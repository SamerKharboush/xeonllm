# 12: gate: prompt offload on the 35B MoE
Type: task (orchestrator) · Status: resolved (2026-11-12): offload pays on the MoE; text differs GPU-vs-CPU class
Qwen3.6-35B-A3B at -ngl 0, offload on vs off, card 1: 400-token greedy text identical-or-explained,
pp512 N>=3 processes per side alternating. Decides whether ticket 11 extends to MoE.

## 2026-11-12: result (Mocca, high; orchestrator re-ran one pair)

`evidence/12/RESULT.md`. Engine: vendor build-static, series of 92 (core/0082 last), llama-bench sha256
`1a8385e315ae0302`. Ornith-1.0-35B Q6_K, `-ngl 0 -t 12 -b 512 -ub 512 -fa 1`, card 1 (`GGML_METAL_DEVICE_INDEX=1 -dev MTL0`).

- **Prompt (pp512, 3 processes per side alternating, -r 3):** offload on 46.97 / 46.98 / 47.03 tok/s,
  off 31.77 / 31.78 / 31.90. The orchestrator's pair: on 47.01 ± 0.78, off 31.19 ± 0.29 (a lower off
  value than Mocca's three; recorded as a separate observation).
- **Correctness (llama-cli, 400 tokens greedy, ~4k-token prompt):** the guard logs `op offload on:
  MTL0_Private compute buffer 307.63 MiB, cap 1536 MiB`; 1600 of 3200 MUL_MAT_ID and 5460 of 11339
  MUL_MAT sched lines on MTL0 (0 with --no-op-offload); no failed allocation. The text with offload
  is identical across two runs, and differs from the --no-op-offload text from character 79 of the
  reasoning (Metal against CPU/Accelerate summation order, the class the contract reports and does not
  gate); both answers coherent and correct.
- Not byte-identical as on the dense 12B, so ticket 11's MoE exclusion stays until the user decides.
