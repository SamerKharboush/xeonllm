#!/bin/bash
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/23
B=/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin
M=/Users/sam/models
mkdir -p $E/bench2
waitfree() { for i in $(seq 1 150); do
  n=$(pgrep -x llama-server | grep -v '^747$' | wc -l | tr -d ' '); b=$(pgrep -x llama-bench | wc -l | tr -d ' ')
  [ "$n" = 0 ] && [ "$b" = 0 ] && return 0; sleep 2; done; echo "BUSY TIMEOUT" >> $E/serialC.log; }
one() { # model ub tag arm
  waitfree
  local envs=""; [ "$4" = w64 ] && envs="TOSH_FA_PF_W64=1"
  echo "START $3 $4 $(date +%H:%M:%S)" >> $E/serialC.log
  env GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 $envs perl -e 'alarm 1800; exec @ARGV' $B/llama-bench \
    -m $M/$1 -dev MTL0 -ngl 99 -fa 1 -ub $2 -b 2048 -p 512 -n 128 -d 6144 -r 3 -o csv \
    > $E/bench2/$3-$4.csv 2> $E/bench2/$3-$4.err
  echo "END $3 $4 $(date +%H:%M:%S) rc=$?" >> $E/serialC.log
  ls -t /Library/Logs/DiagnosticReports/ | head -3 >> $E/serialC.log
  sleep 8
}
for arm in new w64 new w64; do one Qwen3-0.6B-Q8_0.gguf 512 b06 $arm; done
for arm in new w64 new w64; do one Qwen3-4B-Q4_K_M.gguf 128 b4 $arm; done
echo DONE-C >> $E/serialC.log
