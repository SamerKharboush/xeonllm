#!/bin/bash
# beta8 ticket 09 steps 3, 5, 6 (2026-11-07, after the second cold cycle) + beta7 ticket 05 LFM3 gate cell.
# Every GPU program under a perl alarm. Private buffers only. Models <= 5.0 GB on one card.
D=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/09
B=/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin
S=/Users/sam/firellama/vendor/llama.cpp/build-static/bin
M=/Users/sam/models
A="perl -e alarm(900);exec(@ARGV)"
echo "## $(date) dist llama-bench sha256 $(shasum -a 256 $B/llama-bench | cut -c1-16); build-static llama-bench $(shasum -a 256 $S/llama-bench | cut -c1-16) llama-server $(shasum -a 256 $S/llama-server | cut -c1-16)"
echo "## last gpuRestart $(ls -t /Library/Logs/DiagnosticReports/*.gpuRestart | head -1)"
for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K Qwen3-8B-Q4_K_M; do for c in 0 1; do
  echo "## decode card $c $m"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $A $B/llama-bench -m $M/$m.gguf -ngl 99 -p 0 -n 128 -r 5 -fa 1 -o csv 2>>$D/engine2.err | tail -1
done; done
for m in Qwen3-4B-Q4_K_M Qwen3-8B-Q4_K_M; do for c in 0 1; do
  echo "## verify card $c $m"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $A $B/llama-bench -m $M/$m.gguf -ngl 99 -p 1,2,4,8 -n 0 -r 5 -fa 1 -o csv 2>>$D/engine2.err | tail -4
done; done
for c in 0 1; do
  echo "## lfm3 bench card $c (build-static, 0079)"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $A $S/llama-bench -m $M/LFM3-1.7B-F16.gguf -ngl 99 -p 512 -n 128 -r 5 -fa 1 -o csv 2>>$D/engine2.err | tail -2
done
P='{"messages":[{"role":"user","content":"What is the capital of France? Answer in one sentence."}],"max_tokens":160,"temperature":0}'
echo "## lfm3 text card 0 ngl 99"
GGML_METAL_DEVICE_INDEX=0 TOSH_FA_AMD=1 $A $S/llama-server -m $M/LFM3-1.7B-F16.gguf -ngl 99 -c 4096 --jinja --port 18122 --host 127.0.0.1 > $D/lfm3-card0-160.log 2>&1 & SP=$!
for i in $(seq 1 120); do curl -sf http://127.0.0.1:18122/health >/dev/null && break; kill -0 $SP 2>/dev/null || break; sleep 1; done
curl -s -m 300 http://127.0.0.1:18122/v1/chat/completions -d "$P" > $D/lfm3-card0-160.json
kill -INT $SP; wait $SP 2>/dev/null
python3 -c "
import json;a=json.load(open('$D/lfm3-card0-160.json'))['choices'][0]['message'];b=json.load(open('$D/lfm3-host-160.json'))['choices'][0]['message']
print('card0 content', repr(a.get('content')), 'vs host:', 'IDENTICAL' if (a.get('reasoning_content'),a.get('content'))==(b.get('reasoning_content'),b.get('content')) else 'DIFFER')"
echo "## last gpuRestart $(ls -t /Library/Logs/DiagnosticReports/*.gpuRestart | head -1)"
echo "### done $(date)"
