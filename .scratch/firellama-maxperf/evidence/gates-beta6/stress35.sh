#!/bin/bash
# Contract section 4 for the 35B on the fixed beta.6 app: its real launch is the expert tier on
# card 1 (--dynamic-moe on, GGML_METAL_DEVICE_INDEX=1), no drafter (the planner turns it off).
# Modes: tensor = the app's flags as logged; ngl0 = the CPU reference. Hard links, not symlinks.
cd /Users/sam/firellama
O=/Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/out/set
rm -rf $O/ornith-1.0-35b-Q6_K
APPLOG=$O/ornith-1.0-35b-Q6_K.fixed.applog OUT=$O/ornith-1.0-35b-Q6_K MODES="tensor ngl0" \
  NGL0_CELLS="band16 band300 band1100" CELL_TIMEOUT=2700 \
  scripts/stress-release.sh /Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin /Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/models35/ornith-1.0-35b-Q6_K.gguf
for t in $O/ornith-1.0-35b-Q6_K/*.cells.tsv; do echo "-- $(basename $t)"; cat $t; done
cat $O/ornith-1.0-35b-Q6_K/tables/stress.tsv | grep -E "identical|REFUSED|FAIL"
echo "### done"
