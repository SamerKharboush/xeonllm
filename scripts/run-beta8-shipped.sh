#!/bin/bash
# Beta 8 shipped settings: the app still builds TOSH_* switches on its XEON_* engine.
# Run after phase 1; the phase-1 beta8 rows used XEON_* and must be replaced.
set -u
cd /Users/sam/firellama
OUT=.scratch/xeonllm-0-2/evidence/01/matrix-beta8-shipped.tsv
LOG=.scratch/xeonllm-0-2/evidence/01/matrix-beta8-shipped.log
D=.scratch/xeonllm-0-2/evidence/01/configs
E=.scratch/xeonllm-0-2/engines
ENG=$E/XeonLLM-v0.87.31-beta.8-noavx2/bin
MODEL35=/Users/sam/firellama/.scratch/xeonllm-v0-1/gates-v01/models35/ornith-1.0-35b-Q6_K.gguf
[ -f "$OUT" ] || printf 'timestamp\tbuild\tengine_sha16\targs_set\tmodel\tmode\trun\tstatus\tpp_ts\ttg_ts\tpp_len\ttg_len\tmethod\n' > "$OUT"
MODEL_PATH_mini=/Users/sam/models/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-Q8_0.gguf
MODEL_PATH_lfm=/Users/sam/models/LFM3-1.7B-F16.gguf
MODEL_PATH_q06=/Users/sam/models/Qwen3-0.6B-Q8_0.gguf
MODEL_PATH_q4=/Users/sam/models/Qwen3-4B-Q6_K.gguf
for m in mini lfm q06 q4; do
  eval "mp=\$MODEL_PATH_$m"
  case "$m" in mini) envf="$D/beta-native-tensor.env" ;; *) envf="$D/beta-native-layer.env" ;; esac
  for mode in bench real; do
    echo "=== $(date '+%F %T') beta8 shipped $m $mode" >> "$LOG"
    ./scripts/bench-builds.sh --engine "$ENG" --model "$mp" --mode "$mode" \
      --args-file "$D/beta8-$m-$mode.args" --env-file "$envf" --build beta8 \
      --args-set shipped --label "beta8-$m-$mode-shipped-tosh" --reps 3 --n-predict 128 \
      --switch-namespace 'TOSH_*' --translation 'as shipped TOSH_* names; inert on XEON_* engine' \
      --out "$OUT" >> "$LOG" 2>&1
  done
done
# 35B shipped beta8: app's TOSH_* switches are inert; use 0.1.1 real args with TOSH_* env.
extra="$D/35-expert-tosh.env"; dryenv="$D/.35-dry-beta8-tosh.env"
{ cat "$extra"; printf 'XEON_AUTO_DRY_RUN=exit\n'; } > "$dryenv"
( cd /Users/sam/firellama || exit 1
  env $(cat "$dryenv") perl -e 'alarm 1800; exec @ARGV' "$ENG/llama-server" \
    -m "$MODEL35" --host 127.0.0.1 --port 18201 $(cat "$D/011-35-real.args") \
    > "$D/.35-dry-beta8-tosh.log" 2>&1
)
if python3 -I scripts/bench-builds-helper.py plan35 --file "$D/.35-dry-beta8-tosh.log" >> "$LOG" 2>&1; then
  ./scripts/bench-builds.sh --engine "$ENG" --model "$MODEL35" --mode real \
    --args-file "$D/011-35-real.args" --env-file "$extra" --build beta8 \
    --args-set shipped --label "beta8-35-real-shipped-tosh" --reps 3 --n-predict 128 \
    --switch-namespace 'TOSH_*' --translation 'as shipped TOSH_* names; inert on XEON_* engine' \
    --plan-file "$D/.35-dry-beta8-tosh.log" --out "$OUT" >> "$LOG" 2>&1
else
  ./scripts/bench-builds.sh --engine "$ENG" --model "$MODEL35" --mode real \
    --args-file "$D/011-35-real.args" --env-file "$extra" --build beta8 \
    --args-set shipped --label "beta8-35-real-unsafe" --reps 3 --n-predict 128 \
    --switch-namespace 'TOSH_*' --translation 'as shipped TOSH_* names; inert on XEON_* engine' \
    --plan-file "$D/.35-dry-beta8-tosh.log" --out "$OUT" >> "$LOG" 2>&1
fi
echo "DONE $(date '+%F %T')" >> "$LOG"