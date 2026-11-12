#!/bin/bash
# step 4 arms: 8 runs on one arm (default ub): cache-ram 0 (c1..c4) then TOSH_FA_PF_W64=1 (w1..w4)
set -u
EV=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/24
export B=${B:-/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin}
export LOGDIR=$EV/step4
mkdir -p "$LOGDIR"
cd /Users/sam/firellama/.scratch/beta8-unified-engine
run() { label=$1; shift; echo "== $label $(date +%T)"; perl -e 'alarm 1800; exec @ARGV' bash evidence/gates-beta8/repro.sh "$label" "$@"; echo "== $label done $(date +%T)"; }
for l in c1 c2 c3 c4; do run "$l" --cache-ram 0; done
for l in w1 w2 w3 w4; do TOSH_FA_PF_W64=1 run "$l"; done
echo "ALLDONE $(date +%T)"