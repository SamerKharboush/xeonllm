#!/bin/bash
# The fixed beta.6 app on the 35B (hard links in models35/): read the placement header, stop.
cd /Users/sam/firellama
LOGS="$HOME/Library/Application Support/XeonLLMGateTest/logs"
rm -rf "$LOGS"
bash /Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/testapp.sh /Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/models35/ornith-1.0-35b-Q6_K.gguf 32768 tensor
for i in $(seq 1 200); do
  f=$(ls -t "$LOGS"/server-*.log 2>/dev/null | head -1)
  [ -n "$f" ] && grep -q "listening on\|exited with\|error loading model" "$f" && break
  sleep 3
done
cp "$f" /Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/out/set/ornith-1.0-35b-Q6_K.fixed.applog
pkill -f "/Users/sam/firellama/.scratch/firellama-maxperf/evidence/gates-beta6/testapp/XeonLLM.app/Contents/MacOS"
sleep 12
echo "### done"
