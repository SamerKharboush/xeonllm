#!/bin/bash
# summarize beta7 runs: label, status/s, TEXT line, prompt tok/s, eval tok/s, teardown mismatch lines
EV=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/24
cd "$EV/beta7" || exit 1
printf "%-4s %-8s %-8s %-8s %-8s %-8s %-8s %s\n" label status secs text prompt evalsec mismatch
for f in repro-*.out; do
  label=${f#repro-}; label=${label%.out}
  st=$(head -1 "$f" | awk '{print $1}')
  sec=$(head -1 "$f" | awk '{print $2}')
  txt=$(tail -1 "$f" | cut -c1-30)
  log=repro-$label.log
  pp=$(grep "prompt eval time" "$log" 2>/dev/null | sed -E 's/.*\(([0-9.]+) ms per token.*/\1/')
  ev=$(grep "eval time =" "$log" 2>/dev/null | sed -E 's/.*\(([0-9.]+) ms per token.*/\1/')
  mm=$(grep -c "does not match" "$log" 2>/dev/null)
  printf "%-4s %-8s %-8s %-8s %-8s %-8s %-8s %s\n" "$label" "$st" "$sec" "$txt" "$pp" "$ev" "$mm" "$(grep -c 'Timeout' "$log" 2>/dev/null)"
done