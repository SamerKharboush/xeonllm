#!/bin/bash
# Contract section 4 on the rebuilt beta.7 app: for each model in the stress set, the test app
# (dev.xeonllm.gatetest, tensor split over both cards, saved ctx 32768) launches it once, its
# server log is kept, and scripts/stress-release.sh drives the engine with that launch.
# The 14B runs in the loop (its ctx-fit launch at a saved 32768).
# both cards (the stress script refuses one card). Never port 8080.
cd /Users/sam/firellama
G=$PWD/.scratch/beta8-unified-engine/evidence/gates-beta7
O=$G/out2/set
mkdir -p $O
BIN=$PWD/dist/XeonLLM.app/Contents/Resources/bin
LOGS="$HOME/Library/Application Support/XeonLLMGateTest/logs"
M=/Users/sam/models
# the 35B has no <stem>.dflash.gguf beside it; links here give the app and the script one
L=$G/models35; mkdir -p $L
ln -sf $M/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf $L/ornith-1.0-35b-Q6_K.gguf
ln -sf $M/Qwen3.6-35B-A3B-DFlash-Q8_0.gguf $L/ornith-1.0-35b-Q6_K.dflash.gguf

appstart() {   # model -> $O/<stem>.applog
    local stem; stem=$(basename "$1" .gguf)
    rm -rf "$LOGS"
    bash $G/testapp.sh "$1" 32768 tensor
    for i in $(seq 1 200); do
        f=$(ls -t "$LOGS"/server-*.log 2>/dev/null | head -1)
        [ -n "$f" ] && grep -q "listening on\|exited with\|error loading model" "$f" && break
        sleep 3
    done
    cp "$f" "$O/$stem.applog"
    pkill -f "$G/testapp/XeonLLM.app/Contents/MacOS"
    sleep 12
    echo "== $stem"; grep -E "^ (placement|context|dflash|args):" "$O/$stem.applog" | cut -c1-220
}

run() {   # model modes
    local stem; stem=$(basename "$1" .gguf)
    appstart "$1"
    APPLOG=$O/$stem.applog OUT=$O/$stem MODES="$2" NGL0_CELLS="band16 band300 band1100" \
        scripts/stress-release.sh $BIN "$1"
    for t in $O/$stem/*.cells.tsv; do echo "-- $(basename $t): $(cut -f2 $t | sort | uniq -c | tr '\n' ' ')"; done
    grep -h "identical\|drafter" $O/$stem/tables/*.tsv 2>/dev/null
}

for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K Qwen3-8B-Q4_K_M Qwen3-14B-Q4_K_M Nemotron-3.5-Bolt-E4B-Q4_K_M LFM3-1.7B-F16; do
    echo "### $m"; run $M/$m.gguf "tensor layer ngl0"
done
echo "### Ternary-Bonsai-2-27B-PQ2_0"; run $M/Ternary-Bonsai-2-27B-PQ2_0.gguf "tensor layer ngl0"
echo "### ornith-1.0-35b-Q6_K"; run $L/ornith-1.0-35b-Q6_K.gguf "tensor draft"
bash $G/testapp.sh clean
echo "### done"
