#!/bin/bash
# usage: run2.sh <name> [env=val ...] -- <llama-bench args...>
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/22/repro
W=/Users/sam/Library/Caches/xeonllm-wt-fa
M=/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf
n=$1; shift
envs=()
while [ "$1" != "--" ]; do envs+=("$1"); shift; done
shift
cd $W
export GGML_METAL_DEVICE_INDEX=1
env "${envs[@]}" perl -e 'alarm 1800; exec @ARGV' ./build-fa/bin/llama-bench -m $M -ngl 0 "$@" -o csv > $E/$n.csv 2> $E/$n.err
echo "$n rc=$?" >> $E/rc-after.txt
