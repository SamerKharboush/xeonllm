#!/bin/bash
# Sequential cross-build matrix for the small models. One GPU job at a time; runner enforces it.
set -u
cd /Users/sam/firellama
OUT=.scratch/xeonllm-0-2/evidence/01/matrix-small.tsv
LOG=.scratch/xeonllm-0-2/evidence/01/matrix-small.log
PIDFILE=.scratch/xeonllm-0-2/evidence/01/matrix-small.pid
D=.scratch/xeonllm-0-2/evidence/01/configs
E=.scratch/xeonllm-0-2/engines
BUILDS=(beta4 beta5 beta6 beta7 beta8 010 011)
MODELS=(mini lfm q06 q4)
MODEL_PATH_mini=/Users/sam/models/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-GGUF/MiniCPM5-1B-Claude-Opus-Fable5-Thinking-Q8_0.gguf
MODEL_PATH_lfm=/Users/sam/models/LFM3-1.7B-F16.gguf
MODEL_PATH_q06=/Users/sam/models/Qwen3-0.6B-Q8_0.gguf
MODEL_PATH_q4=/Users/sam/models/Qwen3-4B-Q6_K.gguf
ENGINE_beta4=$E/XeonLLM-v0.87.31-beta.4-noavx2/bin
ENGINE_beta5=$E/XeonLLM-v0.87.31-beta.5-noavx2/bin
ENGINE_beta6=$E/XeonLLM-v0.87.31-beta.6-noavx2/bin
ENGINE_beta7=$E/XeonLLM-v0.87.31-beta.7-noavx2/bin
ENGINE_beta8=$E/XeonLLM-v0.87.31-beta.8-noavx2/bin
ENGINE_010=$E/XeonLLM-v0.1.0-noavx2/bin
ENGINE_011=$E/XeonLLM-v0.1.1-noavx2/bin
[ -f "$OUT" ] || printf 'timestamp\tbuild\tengine_sha16\targs_set\tmodel\tmode\trun\tstatus\tpp_ts\ttg_ts\tpp_len\ttg_len\tmethod\n' > "$OUT"
echo $$ > "$PIDFILE"
for m in "${MODELS[@]}"; do
  eval "mp=\$MODEL_PATH_$m"
  for b in "${BUILDS[@]}"; do
    eval "eng=\$ENGINE_$b"
    case "$b" in
      beta4|beta5|beta6|beta7) native_env=$D/beta-native-layer.env; translated_env=$D/xeon-translated-layer.env ;;
      beta8) native_env=$D/beta-native-layer.env; translated_env=$D/xeon-native-layer.env ;;
      *) native_env=$D/xeon-native-layer.env; translated_env=$D/xeon-native-layer.env ;;
    esac
    if [ "$m" = mini ]; then
      case "$b" in
        beta4|beta5|beta6|beta7) native_env=$D/beta-native-tensor.env; translated_env=$D/xeon-translated-tensor.env ;;
        *) native_env=$D/xeon-native-tensor.env; translated_env=$D/xeon-native-tensor.env ;;
      esac
    fi
    for mode in bench real; do
      # (a) this build's own app args
      ./scripts/bench-builds.sh --engine "$eng" --model "$mp" --mode "$mode" \
        --args-file "$D/$b-$m-$mode.args" --env-file "$native_env" \
        --build "$b" --args-set shipped --label "$b-$m-$mode-shipped" \
        --reps 3 --n-predict 128 --out "$OUT" >> "$LOG" 2>&1
      # (b) 0.1.1 app args on this engine; skip exact duplicates on 0.1.0/0.1.1
      if [ "$b" = 010 ] || [ "$b" = 011 ]; then
        echo "skip engine-only duplicate $b $m $mode" >> "$LOG"
      else
        ./scripts/bench-builds.sh --engine "$eng" --model "$mp" --mode "$mode" \
          --args-file "$D/011-$m-$mode.args" --env-file "$translated_env" \
          --build "$b" --args-set 011 --label "$b-$m-$mode-engineonly" \
          --reps 3 --n-predict 128 --out "$OUT" >> "$LOG" 2>&1
      fi
    done
  done
done
date '+%F %T' >> "$LOG"