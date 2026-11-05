#!/bin/bash
# beta8 ticket 09: decode, verify curve, LFM3 on a card. Both cards, cards alternating.
D=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/09
B=/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin
S=/Users/sam/firellama/vendor/llama.cpp/build-static/bin
M=/Users/sam/models
echo "## dist llama-bench sha256 $(shasum -a 256 $B/llama-bench | cut -c1-16); build-static llama-server $(shasum -a 256 $S/llama-server | cut -c1-16)"
for c in 0 1; do for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K Qwen3-8B-Q4_K_M; do
  echo "## decode card $c $m"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -p 0 -n 128 -r 5 -fa 1 -o csv 2>>$D/engine.err | tail -1
done; done
for c in 0 1; do for m in Qwen3-4B-Q4_K_M Qwen3-8B-Q4_K_M; do
  echo "## verify card $c $m"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -p 1,2,4,8 -n 0 -r 5 -fa 1 -o csv 2>>$D/engine.err | tail -4
done; done
P='{"messages":[{"role":"user","content":"What is the capital of France? Answer in one sentence."}],"max_tokens":40,"temperature":0}'
for c in 0 1; do
  echo "## lfm3 card $c ngl 99"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $S/llama-server -m $M/LFM3-1.7B-F16.gguf -ngl 99 -c 4096 --jinja --port 18122 --host 127.0.0.1 > $D/lfm3-card$c.log 2>&1 & SP=$!
  for i in $(seq 1 90); do curl -sf http://127.0.0.1:18122/health >/dev/null && break; kill -0 $SP 2>/dev/null || break; sleep 1; done
  curl -s http://127.0.0.1:18122/v1/chat/completions -d "$P" > $D/lfm3-card$c.json
  python3 -c "import sys,json;d=json.load(open('$D/lfm3-card$c.json'));m=d['choices'][0]['message'];print('card $c', round(d['timings']['predicted_per_second'],1),'t/s', repr((m.get('content') or '')[:150]))" 2>&1 | tail -1
  kill -INT $SP 2>/dev/null; wait $SP 2>/dev/null
done
echo "### done"
