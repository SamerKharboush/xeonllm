#!/bin/bash
# extra default-ub runs with the worktree build, same repro (d7..d10)
set -u
EV=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/24
export B=${B:-/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin}
export LOGDIR=$EV/extra
mkdir -p "$LOGDIR"
cd /Users/sam/firellama/.scratch/beta8-unified-engine
run() { label=$1; shift; echo "== $label $(date +%T)"; perl -e 'alarm 1800; exec @ARGV' bash evidence/gates-beta8/repro.sh "$label" "$@"; echo "== $label done $(date +%T)"; }
for l in d7 d8 d9 d10; do run "$l"; done
echo "ALLDONE $(date +%T)"