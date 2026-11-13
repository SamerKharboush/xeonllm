# 25b: TOSH_FA_PF_W64=1 at -ngl 0 on the four other moved models (2026-11-13)

Written by the orchestrator from the saved files: the Mocca relay (briefs/25b-relay.out) ended rc=130 with no
final message after all four runs had finished. Engine: shipped beta 8 dist/XeonLLM.app/Contents/Resources/bin
(llama-server 63eb2a01af361672), MODES=ngl0, cells band16 band300 band1100 in the gate's order, app launch
flags from gates-beta8/out/set/<stem>.applog, env TOSH_FA_PF_W64=1.

All cells PASS (<stem>/<stem>-ngl0.cells.tsv). compare.txt:
- Qwen3-4B-Q4_K_M, Qwen3-4B-Q6_K, Qwen3-14B-Q4_K_M: identical to beta.7 on all three cells; the cell that
  moved in beta 8 differs from beta 8 (@143, @51, @6). 0083 is the whole cause on these models.
- Ternary-Bonsai-2-27B-PQ2_0: identical to beta 8, still differs from beta.7 (band300 @226). Not 0083: the
  GGUF header reads qwen35, attention.key_length 256, and 0083 acts on head 64/128 only. Open: step 25c.
Knob evidence: Qwen3-14B and Ternary knob-env.txt list TOSH_FA_PF_W64=1 in the server's environment
(trimmed by the orchestrator to TOSH_/GGML_ lines; the raw dump held a session token). The 4B runs have no
env dump; their text moving to beta.7 shows the knob took effect.
No GGML_ASSERT, "kernel not found" or "@@@@" in w64-set (grep). DiagnosticReports: no name added since
diag-before.txt.
