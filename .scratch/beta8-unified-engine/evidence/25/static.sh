#!/bin/bash
# usage: static.sh <label> <builddir>
set -u
LABEL="$1"; BUILD="${2:-build-fa}"; [ -d "$BUILD" ] || BUILD="/Users/sam/Library/Caches/xeonllm-wt-fa/$2"
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/25
{
echo "label $LABEL  date $(date '+%F %T')"
for B in "$BUILD" /Users/sam/firellama/vendor/llama.cpp/build-static; do
  echo "== $B"
  grep -m1 CMAKE_HOME_DIRECTORY: $B/CMakeCache.txt 2>/dev/null
  grep -E '^(CMAKE_CXX_FLAGS|CMAKE_OSX_ARCHITECTURES|CMAKE_OSX_DEPLOYMENT_TARGET|GGML_NATIVE|GGML_SSE42|GGML_AVX|GGML_AVX2|GGML_FMA|GGML_F16C|GGML_BMI2|GGML_OPENMP|GGML_ACCELERATE|GGML_LLAMAFILE|GGML_CPU_REPACK|GGML_CPU_ALL_VARIANTS|TOSH_ENABLE_DYNAMIC_MOE):' $B/CMakeCache.txt 2>/dev/null
  grep -h '^CXX_FLAGS =' $B/ggml/src/CMakeFiles/ggml-cpu.dir/flags.make 2>/dev/null
  for o in $B/ggml/src/CMakeFiles/ggml-cpu.dir/ggml-cpu/*.o; do
    [ -f "$o" ] && printf '%s %s %s\n' "$(stat -f '%Sm' -t '%F %T' "$o")" "$(stat -f '%z' "$o")" "${o#$B/}"
  done
done
cd /Users/sam/Library/Caches/xeonllm-wt-fa
git log --format='%h %s' -7 | cat
git status --short
} > "$E/static-$LABEL.txt" 2>&1
cat "$E/static-$LABEL.txt"