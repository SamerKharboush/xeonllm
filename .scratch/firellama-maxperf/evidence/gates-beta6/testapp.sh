#!/bin/bash
# Launch a copy of dist/XeonLLM.app as dev.xeonllm.gatetest with its own data folder
# (XeonLLMGateTest) and port, so the user's app, defaults and Application Support are
# never touched. Usage: testapp.sh <model.gguf> <ctx> <layer|tensor>; testapp.sh clean
set -euo pipefail
cd /Users/sam/firellama
D=.scratch/firellama-maxperf/evidence/gates-beta6
T=$D/testapp/XeonLLM.app
DOM=dev.xeonllm.gatetest
if [ "${1:-}" = clean ]; then
    pkill -f "$PWD/$T/Contents/MacOS" 2>/dev/null || true
    defaults delete "$DOM" 2>/dev/null || true
    rm -rf "$HOME/Library/Application Support/XeonLLMGateTest" "$D/testapp"
    echo cleaned; exit 0
fi
MODEL=$1 CTX=$2 SPLIT=$3
rm -rf "$D/testapp"; mkdir -p "$D/testapp"
ditto dist/XeonLLM.app "$T"
plutil -replace CFBundleIdentifier -string "$DOM" "$T/Contents/Info.plist"
plutil -replace TOSHDataFolder -string XeonLLMGateTest "$T/Contents/Info.plist"
codesign --force --deep -s - "$T" >/dev/null 2>&1
defaults delete "$DOM" 2>/dev/null || true
defaults write "$DOM" migratedFromToshLLM -bool true          # no Keychain or folder copy from ToshLLM
defaults write "$DOM" migratedFromToshLLMFolderV2 -bool true
defaults write "$DOM" onboardingDone -bool true
defaults write "$DOM" lang -string en
defaults write "$DOM" modelsDir -string /Users/sam/models
defaults write "$DOM" modelPath -string "$MODEL"
defaults write "$DOM" ctx -int "$CTX"
defaults write "$DOM" contextAutomatic -bool false
defaults write "$DOM" multiGPU -bool true
defaults write "$DOM" splitMode -string "$SPLIT"
defaults write "$DOM" port -int 18099
defaults write "$DOM" autoStart -bool true
defaults write "$DOM" updateAutoCheck -bool false
open -n "$T"
echo "launched $T ($MODEL ctx=$CTX $SPLIT, port 18099)"
