#!/bin/bash
# Part 2: 35B real matrix, then 0.1.1 app args on the older engines.
# Run only after run-matrix.sh phase 1 has finished.
set -u
cd /Users/sam/firellama
OUT=.scratch/xeonllm-0-2/evidence/01/matrix.tsv
LOG=.scratch/xeonllm-0-2/evidence/01/matrix-part2.log
D=.scratch/xeonllm-0-2/evidence/01/configs
E=.scratch/xeonllm-0-2/engines
MODEL35=/Users/sam/firellama/.scratch/xeonllm-v0-1/gates-v01/models35/ornith-1.0-35b-Q6_K.gguf
BUILDS=(beta4 beta5 beta6 beta7 beta8 010 011)
ENGINE_beta4=$E/XeonLLM-v0.87.31-beta.4-noavx2/bin
ENGINE_beta5=$E/XeonLLM-v0.87.31-beta.5-noavx2/bin
ENGINE_beta6=$E/XeonLLM-v0.87.31-beta.6-noavx2/bin
ENGINE_beta7=$E/XeonLLM-v0.87.31-beta.7-noavx2/bin
ENGINE_beta8=$E/XeonLLM-v0.87.31-beta.8-noavx2/bin
ENGINE_010=$E/XeonLLM-v0.1.0-noavx2/bin
ENGINE_011=$E/XeonLLM-v0.1.1-noavx2/bin
free_pct() { memory_pressure | tail -1 | sed -n 's/.*free percentage: \([0-9][0-9]*\)%.*/\1/p'; }
wait_mem() {
  while :; do
    pct="$(free_pct)"
    [ -n "$pct" ] && [ "$pct" -ge 50 ] && return 0
    echo "waiting memory: ${pct:-unknown}%" >> "$LOG"
    sleep 10
  done
}

for b in "${BUILDS[@]}"; do
  eval "eng=\$ENGINE_$b"
  case "$b" in
    beta4|beta5|beta6|beta7)
      extra="$D/35-expert-tosh.env"; dry="TOSH_AUTO_DRY_RUN=exit"; ns="TOSH_*"; tr="0.1.1 XEON_* names translated to TOSH_*" ;;
    beta8)
      extra="$D/35-expert.env"; dry="XEON_AUTO_DRY_RUN=exit"; ns="XEON_*"; tr="native XEON_* names (0.1.1 args)" ;;
    *)
      extra="$D/35-expert.env"; dry="XEON_AUTO_DRY_RUN=exit"; ns="XEON_*"; tr="native XEON_* names" ;;
  esac
  dryenv="$D/.35-dry2-$b.env"
  { cat "$extra"; printf '%s\n' "$dry"; } > "$dryenv"
  wait_mem
  echo "=== $(date '+%F %T') 35B dry-run build=$b mem=$(free_pct)% ns=$ns" >> "$LOG"
  env $(cat "$dryenv") perl -e 'alarm 1800; exec @ARGV' "$eng/llama-server" \
    -m "$MODEL35" --host 127.0.0.1 --port 18201 $(cat "$D/011-35-real.args") \
    > "$D/.35-dry2-$b.log" 2>&1
  echo "dry_rc=$?" >> "$LOG"
  if python3 -I scripts/bench-builds-helper.py plan35 --file "$D/.35-dry2-$b.log" >> "$LOG" 2>&1; then
    wait_mem
    ./scripts/bench-builds.sh --engine "$eng" --model "$MODEL35" --mode real \
      --args-file "$D/011-35-real.args" --env-file "$extra" --build "$b" \
      --args-set 011 --label "$b-35-real-011" --reps 3 --n-predict 128 \
      --switch-namespace "$ns" --translation "$tr" \
      --plan-file "$D/.35-dry2-$b.log" --out "$OUT" >> "$LOG" 2>&1
  else
    echo "NOT RUN: unsafe 35B $b: dry-run plan failed VRAM gate" >> "$LOG"
    ./scripts/bench-builds.sh --engine "$eng" --model "$MODEL35" --mode real \
      --args-file "$D/011-35-real.args" --env-file "$extra" --build "$b" \
      --args-set 011 --label "$b-35-real-unsafe" --reps 3 --n-predict 128 \
      --switch-namespace "$ns" --translation "$tr" \
      --plan-file "$D/.35-dry2-$b.log" --out "$OUT" >> "$LOG" 2>&1
  fi
done

MODEL_PATH_mini=/Users/sam/models/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-Q8_0.gguf
MODEL_PATH_lfm=/Users/sam/models/LFM3-1.7B-F16.gguf
MODEL_PATH_q06=/Users/sam/models/Qwen3-0.6B-Q8_0.gguf
MODEL_PATH_q4=/Users/sam/models/Qwen3-4B-Q6_K.gguf
for m in mini lfm q06 q4; do
  eval "mp=\$MODEL_PATH_$m"
  for b in "${BUILDS[@]}"; do
    [ "$b" = 010 ] || [ "$b" = 011 ] && { echo "skip engine-only duplicate $b $m" >> "$LOG"; continue; }
    eval "eng=\$ENGINE_$b"
    case "$b" in
      beta4|beta5|beta6|beta7)
        case "$m" in mini) envf="$D/xeon-translated-tensor.env" ;; *) envf="$D/xeon-translated-layer.env" ;; esac
        ns="TOSH_*"; tr="0.1.1 XEON_* names translated to TOSH_*" ;;
      beta8)
        case "$m" in mini) envf="$D/xeon-native-tensor.env" ;; *) envf="$D/xeon-native-layer.env" ;; esac
        ns="XEON_*"; tr="native XEON_* names (0.1.1 args)" ;;
    esac
    for mode in bench real; do
      wait_mem
      echo "=== $(date '+%F %T') build=$b model=$m mode=$mode args_set=011 env=$(basename "$envf") mem=$(free_pct)%" >> "$LOG"
      ./scripts/bench-builds.sh --engine "$eng" --model "$mp" --mode "$mode" \
        --args-file "$D/011-$m-$mode.args" --env-file "$envf" --build "$b" \
        --args-set 011 --label "$b-$m-$mode-011" --reps 3 --n-predict 128 \
        --switch-namespace "$ns" --translation "$tr" --out "$OUT" >> "$LOG" 2>&1
    done
  done
done
echo "DONE $(date '+%F %T')" >> "$LOG"