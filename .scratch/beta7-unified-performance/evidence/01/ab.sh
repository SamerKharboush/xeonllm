#!/bin/bash
# Ticket 01 gate: the 35B expert tier with its DFlash drafter on the idle card (draft) against
# beta.6's launch with no drafter (base). Dev engine build-static (d81235049 + 88 patches + the
# spec/0073 cross-card head copy), the args the rebuilt app logged. 6 servers alternating
# base/draft, each 1 warmup + 3 measured requests, 128 tokens, temperature 0.
cd /Users/sam/firellama
E=/Users/sam/firellama/.scratch/beta7-unified-performance/evidence/01
BIN=vendor/llama.cpp/build-static/bin/llama-server
A=$(grep -m1 "^ args:" $E/app-35b-crash.applog | sed 's/^ args: //; s/ --path .*//; s/--port 18099/--port 18113/')
eval "set -- $A"; DRAFT=("$@")
BASE=(); skip=0
for a in "${DRAFT[@]}"; do
  if [ $skip -gt 0 ]; then skip=$((skip-1)); continue; fi
  case "$a" in -md|--spec-type|-ngld|-ctkd|-ctvd|-mg|-devd|--split-mode) skip=1; continue;; esac
  BASE+=("$a")
done
echo "draft args: ${DRAFT[*]}" > $E/ab.args; echo "base args: ${BASE[*]}" >> $E/ab.args
echo -e "server\tmode\treq\tpredicted_per_second\tdraft_n\tdraft_n_accepted\tdisplay" > $E/ab.tsv
for s in 1 2 3 4 5 6; do
  if [ $((s % 2)) = 1 ]; then mode=base; else mode=draft; fi
  if [ $mode = base ]; then envs=(TOSH_AUTO_KV=auto GGML_METAL_DEVICE_INDEX=1 TOSH_FA_AMD=1); args=("${BASE[@]}");
  else envs=(TOSH_AUTO_KV=auto GGML_METAL_DEVICE_LIST=1,0 TOSH_FA_AMD=1); args=("${DRAFT[@]}"); fi
  env "${envs[@]}" $BIN "${args[@]}" > $E/ab-$s-$mode.log 2>&1 & P=$!
  for i in $(seq 1 200); do curl -sf http://127.0.0.1:18113/health >/dev/null && break; kill -0 $P 2>/dev/null || break; sleep 3; done
  disp=$(ioreg -n IODisplayWrangler -r -d 1 2>/dev/null | grep -o '"CurrentPowerState"=[0-9]' | head -1)
  for r in 0 1 2 3; do
    curl -s http://127.0.0.1:18113/v1/chat/completions -d '{"messages":[{"role":"user","content":"Write a binary search tree insert function in Python."}],"max_tokens":128,"temperature":0,"cache_prompt":false}' > $E/ab-$s-$mode-r$r.json
    python3 -c "
import json,sys;d=json.load(open('$E/ab-$s-$mode-r$r.json'));t=d['timings'];m=d['choices'][0]['message']
open('$E/ab-$s-$mode-r$r.txt','w').write((m.get('reasoning_content') or '')+'\n---\n'+(m.get('content') or ''))
print('$s\t$mode\t$r\t%.4f\t%s\t%s\t$disp'%(t['predicted_per_second'],t.get('draft_n',0),t.get('draft_n_accepted',0)))" >> $E/ab.tsv
  done
  kill -INT $P; wait $P
  sleep 15
done
echo "### done"
