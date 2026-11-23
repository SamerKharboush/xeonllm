#!/bin/bash
# Cross-build matrix: shipped args per build first for the reported models,
# then 0.1.1 app args on old engines to separate settings from engine changes.
# Order: MiniCPM5, LFM3, 35B, Qwen3-0.6B, Qwen3-4B. One GPU job at a time.
set -u
cd /Users/sam/firellama
OUT=.scratch/xeonllm-0-2/evidence/01/matrix.tsv
LOG=.scratch/xeonllm-0-2/evidence/01/matrix.log
PIDFILE=.scratch/xeonllm-0-2/evidence/01/matrix.pid
D=.scratch/xeonllm-0-2/evidence/01/configs
E=.scratch/xeonllm-0-2/engines
[ -f "$OUT" ] || printf 'timestamp\tbuild\tengine_sha16\targs_set\tmodel\tmode\trun\tstatus\tpp_ts\ttg_ts\tpp_len\ttg_len\tmethod\n' > "$OUT"
echo $$ > "$PIDFILE"
ENGINE_beta4=$E/XeonLLM-v0.87.31-beta.4-noavx2/bin
ENGINE_beta5=$E/XeonLLM-v0.87.31-beta.5-noavx2/bin
ENGINE_beta6=$E/XeonLLM-v0.87.31-beta.6-noavx2/bin
ENGINE_beta7=$E/XeonLLM-v0.87.31-beta.7-noavx2/bin
ENGINE_beta8=$E/XeonLLM-v0.87.31-beta.8-noavx2/bin
ENGINE_010=$E/XeonLLM-v0.1.0-noavx2/bin
ENGINE_011=$E/XeonLLM-v0.1.1-noavx2/bin
BUILDS=(beta4 beta5 beta6 beta7 beta8 010 011)
# phase 1: shipped args, reported models first
PHASE1=(mini lfm q06 q4)
# phase 2: 0.1.1 args on every engine, all small models
PHASE2=(mini lfm q06 q4)

MODEL_PATH_mini=/Users/sam/models/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-Q8_0.gguf
MODEL_PATH_lfm=/Users/sam/models/LFM3-1.7B-F16.gguf
MODEL_PATH_q06=/Users/sam/models/Qwen3-0.6B-Q8_0.gguf
MODEL_PATH_q4=/Users/sam/models/Qwen3-4B-Q6_K.gguf
MODEL_PATH_35=/Users/sam/firellama/.scratch/xeonllm-v0-1/gates-v01/models35/ornith-1.0-35b-Q6_K.gguf

native_env_for() { # build model_prefix
  case "$1" in
    beta4|beta5|beta6|beta7)
      case "$2" in mini) echo "$D/beta-native-tensor.env" ;; *) echo "$D/beta-native-layer.env" ;; esac ;;
    *)
      case "$2" in mini) echo "$D/xeon-native-tensor.env" ;; *) echo "$D/xeon-native-layer.env" ;; esac ;;
  esac
}
translated_env_for() { # build model_prefix
  case "$1" in
    beta4|beta5|beta6|beta7)
      case "$2" in mini) echo "$D/xeon-translated-tensor.env" ;; *) echo "$D/xeon-translated-layer.env" ;; esac ;;
    *)
      case "$2" in mini) echo "$D/xeon-native-tensor.env" ;; *) echo "$D/xeon-native-layer.env" ;; esac ;;
  esac
}
run_one() { # build model_prefix mode args_set args_file env_file
  local b="$1" m="$2" mode="$3" aset="$4" af="$5" ef="$6" mp
  eval "mp=\$MODEL_PATH_$m"
  local eng ns tr
  eval "eng=\$ENGINE_$b"
  ns="XEON_*"; tr="native XEON_* names"
  case "$aset:$b" in
    shipped:beta4|shipped:beta5|shipped:beta6|shipped:beta7) ns="TOSH_*"; tr="native TOSH_* names" ;;
    shipped:beta8) ns="TOSH_*"; tr="as shipped TOSH_* names; inert on XEON_* engine" ;;
    011:beta4|011:beta5|011:beta6|011:beta7) ns="TOSH_*"; tr="0.1.1 XEON_* names translated to TOSH_*" ;;
  esac
  echo "=== $(date '+%F %T') build=$b model=$m mode=$mode args_set=$aset args=$(basename "$af") env=$(basename "$ef") ns=$ns" >> "$LOG"
  ./scripts/bench-builds.sh --engine "$eng" --model "$mp" --mode "$mode" \
    --args-file "$af" --env-file "$ef" --build "$b" --args-set "$aset" \
    --switch-namespace "$ns" --translation "$tr" \
    --label "$b-$m-$mode-$aset" --reps 3 --n-predict 128 --out "$OUT" >> "$LOG" 2>&1
}

for m in "${PHASE1[@]}"; do
  for b in "${BUILDS[@]}"; do
    for mode in bench real; do
      run_one "$b" "$m" "$mode" shipped "$D/$b-$m-$mode.args" "$(native_env_for "$b" "$m")"
    done
  done
done

# 35B: expert-tier launch only. Dry-run plan per engine, VRAM gate before launch.
for b in "${BUILDS[@]}"; do
  eval "eng=\$ENGINE_$b"
  case "$b" in beta4|beta5|beta6|beta7) df="TOSH_AUTO_DRY_RUN=exit"; extra="$D/35-expert-tosh.env" ;; *) df="XEON_AUTO_DRY_RUN=exit"; extra="$D/35-expert.env" ;; esac
  echo "=== $(date '+%F %T') 35B dry-run build=$b" >> "$LOG"
  ( cd "$D" || exit 1
    { cat "$extra"; printf '%s\n' "$df"; } > "$D/.35-dry-$b.env"
    env $(cat "$D/.35-dry-$b.env") perl -e 'alarm 1800; exec @ARGV' "$eng/llama-server" -m "$MODEL_PATH_35" --host 127.0.0.1 --port 18201 $(cat "$D/011-35-real.args") > "$D/.35-dry-$b.log" 2>&1
    echo "dry_rc=$?" >> "$LOG"
  )
  if ./scripts/bench-builds-helper.py plan35 --file "$D/.35-dry-$b.log" >> "$LOG" 2>&1; then
    echo "=== $(date '+%F %T') 35B real build=$b shipped" >> "$LOG"
    ns="XEON_*"; tr="native XEON_* names"
    case "$b" in beta4|beta5|beta6|beta7) ns="TOSH_*"; tr="0.1.1 XEON_* names translated to TOSH_*" ;; beta8) ns="XEON_*"; tr="native XEON_* names (0.1.1 args)" ;; esac
    ./scripts/bench-builds.sh --engine "$eng" --model "$MODEL_PATH_35" --mode real \
      --args-file "$D/011-35-real.args" --env-file "$extra" --build "$b" \
      --args-set shipped --label "$b-35-real-shipped" --reps 3 --n-predict 128 \
      --switch-namespace "$ns" --translation "$tr" \
      --plan-file "$D/.35-dry-$b.log" --out "$OUT" >> "$LOG" 2>&1
  else
    echo "NOT RUN: unsafe 35B $b: dry-run plan failed VRAM gate" >> "$LOG"
    ./scripts/bench-builds.sh --engine "$eng" --model "$MODEL_PATH_35" --mode real \
      --args-file "$D/011-35-real.args" --env-file "$extra" --build "$b" \
      --args-set shipped --label "$b-35-real-unsafe" --reps 3 --n-predict 128 \
      --plan-file "$D/.35-dry-$b.log" --out "$OUT" >> "$LOG" 2>&1
  fi
done

for m in "${PHASE2[@]}"; do
  for b in "${BUILDS[@]}"; do
    if [ "$b" = 010 ] || [ "$b" = 011 ]; then
      echo "skip engine-only duplicate $b $m" >> "$LOG"
      continue
    fi
    for mode in bench real; do
      run_one "$b" "$m" "$mode" 011 "$D/011-$m-$mode.args" "$(translated_env_for "$b" "$m")"
    done
  done
done
echo "DONE $(date '+%F %T')" >> "$LOG"
