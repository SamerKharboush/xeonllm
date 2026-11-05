#!/bin/bash
# Ticket 04 step 0: the cost of k tokens at once on the host, t(k) for k = 1, 2, 4, 8, with the
# core/0022 multi-row switch unset and set. The shipped llama-bench (AVX1 engine), -ngl 0, no card
# visible (GGML_METAL_DEVICES=0 is not a switch here, so op offload is turned off with -nopo 1).
cd /Users/sam/firellama
B=/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin
for m in /Users/sam/models/deepreinforce-ai/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf /Users/sam/models/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0.gguf; do
  for sw in unset set; do
    if [ $sw = set ]; then export GGML_CPU_NO_MULTI_DOT=1; else unset GGML_CPU_NO_MULTI_DOT; fi
    echo "## $(basename $m) GGML_CPU_NO_MULTI_DOT=$sw"
    $B/llama-bench -m $m -ngl 0 -nopo 1 -t 12 -p 1,2,4,8 -n 0 -r 5 -o csv 2>/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/04/step0-$(basename $m .gguf)-$sw.err
  done
done
echo "### done"
