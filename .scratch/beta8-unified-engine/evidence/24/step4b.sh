#!/bin/bash
# step 4 fallback: 4 default-ub runs with the beta.7 engine (labels b1..b4)
set -u
EV=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/24
export B=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/beta7-bin
export LOGDIR=$EV/beta7
mkdir -p "$LOGDIR"
cd /Users/sam/firellama/.scratch/beta8-unified-engine
run() { label=$1; shift; echo "== $label $(date +%T)"; perl -e 'alarm 1800; exec @ARGV' bash evidence/gates-beta8/repro.sh "$label" "$@"; echo "== $label done $(date +%T)"; }
for l in b1 b2 b3 b4; do run "$l"; done
echo "ALLDONE $(date +%T)"