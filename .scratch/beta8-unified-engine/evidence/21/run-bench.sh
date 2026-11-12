#!/bin/sh
# One (model, ub) group: 4 llama-bench processes, alternating new default / TOSH_FA_PF_W64=1.
# usage: run-bench.sh <model-file> <tag> <ub>
B=/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin/llama-bench
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/21
M=$1
TAG=$2
UB=$3

run() {
    side=$1
    rep=$2
    out=$E/bench-$TAG-ub$UB-$side-p$rep.csv
    err=$E/bench-$TAG-ub$UB-$side-p$rep.err
    if [ "$side" = old ]; then
        export TOSH_FA_PF_W64=1
    else
        unset TOSH_FA_PF_W64
    fi
    GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1 perl -e 'alarm 2400; exec @ARGV' \
        $B -m $M -dev MTL0 -ngl 99 -fa 1 -ub $UB -b 2048 -p 512 -n 128 \
        -d 0,2048,6144 -r 2 -o csv > $out 2> $err
    echo "=== $TAG ub$UB $side p$rep exit=$? $(date +%H:%M:%S) ==="
    ls -t /Library/Logs/DiagnosticReports/ | head -3
}

run new 1
run old 1
run new 2
run old 2
