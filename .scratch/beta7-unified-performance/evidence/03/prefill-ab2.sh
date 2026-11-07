#!/bin/bash
# beta7 ticket 03 again (2026-11-07): prefill of a host-placed dense model, op offload on vs off, card 1 (healthy, 13983/13983).
# Engine: worktree xeonllm-wt-offload (series 731b358fd + scheduler fix), llama-bench. Alternating processes.
B=/Users/sam/Library/Caches/xeonllm-wt-offload/build-off/bin/llama-bench
M=/Users/sam/models/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0.gguf
echo "## $(date) llama-bench sha256 $(shasum -a 256 $B | cut -c1-16); last gpuRestart $(ls -t /Library/Logs/DiagnosticReports/*.gpuRestart | head -1)"
for rep in 1 2 3; do for nopo in 0 1; do
  echo "## rep $rep nopo $nopo"
  GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 perl -e 'alarm 1200; exec @ARGV' $B -m $M -dev MTL0 -ngl 0 -nopo $nopo -t 12 -p 512 -n 0 -b 512 -ub 512 -r 3 -fa 1 -o csv 2>>/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/03/prefill-ab2.err | tail -1
done; done
echo "## last gpuRestart $(ls -t /Library/Logs/DiagnosticReports/*.gpuRestart | head -1)"
echo "### done $(date)"
