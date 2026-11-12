#!/bin/bash
# usage: bench.sh <model> <ub> <label>
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/23
B=/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin
m=$1 ub=$2 label=$3; mkdir -p $E/bench
for arm in new w64 new w64; do
  envs=""; [ $arm = w64 ] && envs="TOSH_FA_PF_W64=1"
  echo "== $label $arm" >> $E/bench/bench.log
  env GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 $envs perl -e 'alarm 900; exec @ARGV' $B/llama-bench -m /Users/sam/models/$m -dev MTL0 -ngl 99 -fa 1 -ub $ub -b 2048 -p 512 -n 128 -d 6144 -r 3 -o csv >> $E/bench/bench.log 2>> $E/bench/bench.err
done
echo DONE $label >> $E/bench/bench.log
