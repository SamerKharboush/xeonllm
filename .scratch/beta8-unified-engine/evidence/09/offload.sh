#!/bin/bash
# beta8 ticket 09 step 4: op offload with the scheduler fix, -ngl 0, text check, both cards.
D=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/09
V=/Users/sam/firellama/vendor/llama.cpp
FIX=/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/03/ggml-backend.with-sched-fix.cpp
cp $FIX $V/ggml/src/ggml-backend.cpp
cmake --build $V/build-static -j12 --target llama-server > $D/offload-build.log 2>&1 || { cp $D/ggml-backend.vendor.cpp $V/ggml/src/ggml-backend.cpp; echo BUILD FAILED; exit 1; }
BIN=$V/build-static/bin/llama-server
echo "## fixed llama-server sha256 $(shasum -a 256 $BIN | cut -c1-16)"
P=$(python3 -c "print(' '.join(['The quick brown fox jumps over the lazy dog near the river bank.']*40))")
for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0; do
 n=$(basename $m)
 for c in 0 1; do for off in on off; do
  flag=""; [ $off = off ] && flag="--no-op-offload"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $BIN -m /Users/sam/models/$m.gguf -ngl 0 $flag -c 4096 -t 12 --port 18121 --host 127.0.0.1 > $D/t-$n-c$c-$off.log 2>&1 & S=$!
  for i in $(seq 1 120); do curl -sf http://127.0.0.1:18121/health >/dev/null && break; kill -0 $S 2>/dev/null || break; sleep 1; done
  curl -s http://127.0.0.1:18121/v1/completions -d "{\"prompt\":\"$P Summarise the text above in one sentence:\",\"max_tokens\":32,\"temperature\":0}" > $D/t-$n-c$c-$off.json
  kill -INT $S; wait $S 2>/dev/null
  splits=$(grep -oE "graph splits = [0-9]+" $D/t-$n-c$c-$off.log | tail -1)
  python3 -c "import json;d=json.load(open('$D/t-$n-c$c-$off.json'));print('$n card $c offload=$off', round(d['timings']['prompt_per_second'],1),'t/s pp', '$splits', repr(d['choices'][0]['text'][:110]))"
 done; done
done
cp $D/ggml-backend.vendor.cpp $V/ggml/src/ggml-backend.cpp
cmake --build $V/build-static -j12 --target llama-server llama-bench > $D/offload-restore.log 2>&1 && echo "## restored vendor ggml-backend.cpp and rebuilt" || echo RESTORE BUILD FAILED
cmp $D/ggml-backend.vendor.cpp $V/ggml/src/ggml-backend.cpp && echo "## vendor file identical to before"
echo "### done"
