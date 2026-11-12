#!/bin/bash
# sequential rate runs, one GPU program at a time (repro.sh kills its own server)
set -u
EV=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/24
export B=${B:-/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin}
export LOGDIR=$EV/rate
mkdir -p "$LOGDIR"
cd /Users/sam/firellama/.scratch/beta8-unified-engine
run() { label=$1; shift; echo "== $label $(date +%T)"; perl -e 'alarm 1800; exec @ARGV' bash evidence/gates-beta8/repro.sh "$label" "$@"; echo "== $label done $(date +%T)"; }
run d1
run u1 --ubatch-size 128 --batch-size 128
run d2
run u2 --ubatch-size 128 --batch-size 128
run d3
run u3 --ubatch-size 128 --batch-size 128
run d4
run u4 --ubatch-size 128 --batch-size 128
run d5
run d6
echo "ALLDONE $(date +%T)"