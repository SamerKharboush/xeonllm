#!/bin/bash
# Ticket 03: prefill of a host-placed dense model with and without op offload to card 1.
# gemma4-coding 12B Q8_0 (12.67 GB, over both cards' limit, so the app places it on the host).
cd /Users/sam/firellama
M=/Users/sam/models/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0.gguf
for ub in 512 1024; do for nopo in 1 0 1 0; do
  ( while true; do echo "$(date +%s) $(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -o '"Device Utilization %"=[0-9]*' | tr '\n' ' ')"; sleep 1; done ) > /Users/sam/firellama/.scratch/beta7-unified-performance/evidence/03/util-ub$ub-nopo$nopo-$RANDOM.txt & U=$!
  echo "## ub=$ub nopo=$nopo"
  GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 /Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin/llama-bench -m $M -ngl 0 -nopo $nopo -t 12 -p 1024 -n 0 -b 1024 -ub $ub -r 3 -o csv 2>>/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/03/prefill.err | tail -1
  kill $U
done; done
echo "### done"
