#!/bin/bash
# usage: run_cell.sh <label> <bin-dir> [model] [cells] [extra-server-flag...]
set -u
LABEL="$1"; BIN="$2"; MODEL="${3:-/Users/sam/models/Qwen3-0.6B-Q8_0.gguf}"; CELLS="${4:-band1100}"; shift 4 2>/dev/null || true
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/25
G=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8
STEM="$(basename "$MODEL" .gguf)"
if [ "$STEM" = "Qwen3-8B-Q4_K_M" ]; then ALOG="$G/out/set/Qwen3-8B-Q4_K_M.applog"; else ALOG="$G/out/set/Qwen3-0.6B-Q8_0.applog"; fi
echo "== $(date '+%H:%M:%S') $LABEL bin=$BIN model=$MODEL cells=$CELLS extra=$*"
ps -ax -o pid,comm | grep -E 'llama-(server|bench|cli)' | grep -v grep
cd /Users/sam/firellama || exit 1
APPLOG="$ALOG" OUT="$E/$LABEL" MODES=ngl0 NGL0_CELLS="$CELLS" scripts/stress-release.sh "$BIN" "$MODEL" "$@" \
  > "$E/$LABEL.log" 2>&1
echo "rc=$? $(date '+%H:%M:%S')"
cat "$E/$LABEL/tables/stress.tsv"
ps -ax -o pid,comm | grep -E 'llama-(server|bench|cli)' | grep -v grep