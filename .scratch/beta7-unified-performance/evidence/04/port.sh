#!/bin/bash
# beta7 ticket 04 gate: verify-cost cells with the AVX1 multi-row port, switch unset vs set, alternating.
B=/Users/sam/Library/Caches/xeonllm-wt-avx1/build-avx1/bin/llama-bench
E=/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/04
M=/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf
echo "## llama-bench sha256 $(shasum -a 256 $B | cut -c1-16) (CPU-only AVX1 build, worktree 731b358fd + port)"
for rep in 1 2; do for s in unset set; do
  echo "## rep $rep switch $s"
  if [ $s = set ]; then export GGML_CPU_NO_MULTI_DOT=1; else unset GGML_CPU_NO_MULTI_DOT; fi
  $B -m $M -ngl 0 -t 12 -p 1,2,4,8 -n 0 -r 5 -o csv 2>$E/port-$rep-$s.err | tail -4
  grep -c "multi-row dot ON" $E/port-$rep-$s.err
done; done
echo "### done"
