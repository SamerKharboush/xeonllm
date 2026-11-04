#!/bin/bash
# PQ2 27B evict cells again with a request timeout long enough for its prefill (~19 tok/s over
# ~20k tokens is ~1050 s, over the default 900 s). Both cards; 7.2 GB is under both cards' limit.
cd /Users/sam/firellama
O=/Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/out/set
for mode in tensor layer; do
  rm -rf $O/pq2-evict-$mode
  APPLOG=$O/Ternary-Bonsai-2-27B-PQ2_0.applog OUT=$O/pq2-evict-$mode MODES=$mode CELL_TIMEOUT=2700 \
    CELLS="evict after-evict" scripts/stress-release.sh /Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin /Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf
  cat $O/pq2-evict-$mode/*.cells.tsv
done
echo "### done"
