#!/bin/bash
# strictly serial: one GPU program at a time
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/23
R=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/repro.sh
cd /Users/sam/Library/Caches/xeonllm-wt-fa || exit 1
waitfree() { for i in $(seq 1 120); do
  n=$(pgrep -x llama-server | grep -v '^747$' | wc -l | tr -d ' '); b=$(pgrep -x llama-bench | wc -l | tr -d ' ')
  [ "$n" = 0 ] && [ "$b" = 0 ] && return 0; sleep 2; done; echo "BUSY TIMEOUT" >> $E/serialA.log; }
for spec in "new-3:" "w64-2:TOSH_FA_PF_W64=1" "new-4:" "w64-3:TOSH_FA_PF_W64=1"; do
  label=${spec%%:*}; env=${spec#*:}
  waitfree
  echo "START $label $(date +%H:%M:%S)" >> $E/serialA.log
  env B=$PWD/build-fa/bin LOGDIR=$E/repro2 $env perl -e 'alarm 1800; exec @ARGV' bash $R $label >> $E/repro2/run.log 2>&1
  echo "END $label $(date +%H:%M:%S) rc=$?" >> $E/serialA.log
  ls -t /Library/Logs/DiagnosticReports/ | head -3 >> $E/serialA.log
  sleep 10
done
echo DONE-A >> $E/serialA.log
