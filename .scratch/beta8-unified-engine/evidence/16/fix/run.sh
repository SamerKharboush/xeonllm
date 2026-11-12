#!/bin/bash
# usage: run.sh <tag> <placement> [extra env assignments...]
# placement: one12 | twocard12 | two24
set -u

FIX=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/16/fix
CLI=/Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin/llama-cli
MODEL=/Users/sam/models/Qwen3.6-27B-Heretic-Uncensored-FINETUNE-NEO-CODE-Di-IMatrix-MAX-GGUF/Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf

tag=$1; shift
placement=$1; shift

case "$placement" in
  one12)     envs=( "GGML_METAL_DEVICE_INDEX=1" ) ; ngl=12 ;;
  twocard12) envs=( "GGML_METAL_DEVICE_LIST=0,1" ) ; ngl=12 ;;
  two24)     envs=( "GGML_METAL_DEVICE_LIST=0,1" ) ; ngl=24 ;;
  *) echo "bad placement"; exit 2 ;;
esac

echo "=== $tag ($placement) env: ${envs[*]} extra: $* ===" | tee "$FIX/$tag.cmd"
ls -t /Library/Logs/DiagnosticReports/ | head -3 > "$FIX/$tag.diag-before"

env "${envs[@]}" "$@" perl -e 'alarm 900; exec @ARGV' \
  "$CLI" -m "$MODEL" -c 4096 -ub 128 -b 512 -t 12 -fa on -st --temp 0 -s 1 -n 64 \
  -p "Explain what a binary search tree is." -v -ngl "$ngl" --split-mode layer \
  > "$FIX/$tag.out" 2> "$FIX/$tag.err"
rc=$?

ls -t /Library/Logs/DiagnosticReports/ | head -3 > "$FIX/$tag.diag-after"

# generated text: from the "[Start thinking]" line up to (not including) the "[ Prompt" line
awk '/^\[Start thinking\]/{p=1} /^\[ Prompt/{p=0} p' "$FIX/$tag.out" > "$FIX/$tag.gen"

echo "rc=$rc  gen bytes=$(wc -c < "$FIX/$tag.gen")"
echo "--- first 120 chars ---"
head -c 120 "$FIX/$tag.gen"; echo
echo "--- diag diff ---"
diff "$FIX/$tag.diag-before" "$FIX/$tag.diag-after" && echo "diag unchanged"
