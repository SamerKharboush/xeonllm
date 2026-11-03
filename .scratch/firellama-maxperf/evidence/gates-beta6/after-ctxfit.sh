#!/bin/bash
# After the context fit: evict cells on the layer launch, the tensor launch from the app,
# and the 8B launch header. One model on the cards at a time; never port 8080.
cd /Users/sam/firellama
G=$PWD/.scratch/firellama-maxperf/evidence/gates-beta6
O=$G/out
BIN=$PWD/dist/XeonLLM.app/Contents/Resources/bin
LOGS="$HOME/Library/Application Support/XeonLLMGateTest/logs"
appstart() {   # model ctx split -> copies the new server log to $O/$4
    rm -rf "$LOGS"
    bash $G/testapp.sh "$1" "$2" "$3"
    for i in $(seq 1 100); do
        f=$(ls -t "$LOGS"/server-*.log 2>/dev/null | head -1)
        [ -n "$f" ] && grep -q "listening on\|exited with" "$f" && break
        sleep 3
    done
    cp "$f" "$O/$4"
    pkill -f "$G/testapp/XeonLLM.app/Contents/MacOS"
    sleep 10
    echo "== $4"; grep -E "^ (placement|context|args):" "$O/$4" | cut -c1-200
}

echo "### 1. layer: evict + over-ctx"
rm -rf $O/stress-14b-ctxfit-evict
APPLOG=$O/applog-ctxfit-14b.log OUT=$O/stress-14b-ctxfit-evict MODES="layer" \
    CELLS="evict after-evict over-ctx after-over-ctx" scripts/stress-release.sh $BIN /Users/sam/models/Qwen3-14B-Q4_K_M.gguf
cat $O/stress-14b-ctxfit-evict/*.cells.tsv

echo "### 2. tensor launch from the app"
appstart /Users/sam/models/Qwen3-14B-Q4_K_M.gguf 32768 tensor applog-ctxfit-14b-tensor.log
rm -rf $O/stress-14b-ctxfit-tensor
APPLOG=$O/applog-ctxfit-14b-tensor.log OUT=$O/stress-14b-ctxfit-tensor MODES="tensor" \
    scripts/stress-release.sh $BIN /Users/sam/models/Qwen3-14B-Q4_K_M.gguf
cat $O/stress-14b-ctxfit-tensor/*.cells.tsv

echo "### 3. 8B header"
appstart /Users/sam/models/Qwen3-8B-Q4_K_M.gguf 32768 layer applog-ctxfit-8b.log
echo "### done"
