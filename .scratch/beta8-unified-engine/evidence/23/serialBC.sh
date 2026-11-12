#!/bin/bash
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/23
R=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta8/repro.sh
cd /Users/sam/Library/Caches/xeonllm-wt-fa || exit 1
waitfree() { for i in $(seq 1 150); do
  n=$(pgrep -x llama-server | grep -v '^747$' | wc -l | tr -d ' '); b=$(pgrep -x llama-bench | wc -l | tr -d ' ')
  [ "$n" = 0 ] && [ "$b" = 0 ] && return 0; sleep 2; done; echo "BUSY TIMEOUT" >> $E/serialBC.log; }
# wait for group A to finish
for i in $(seq 1 900); do grep -q DONE-A $E/serialA.log 2>/dev/null && break; sleep 5; done
for spec in "new128-1:" "w64128-1:TOSH_FA_PF_W64=1" "new128-2:" "w64128-2:TOSH_FA_PF_W64=1"; do
  label=${spec%%:*}; env=${spec#*:}
  waitfree
  echo "START $label $(date +%H:%M:%S)" >> $E/serialBC.log
  env B=$PWD/build-fa/bin LOGDIR=$E/repro2 $env perl -e 'alarm 1800; exec @ARGV' bash $R $label --ubatch-size 128 --batch-size 128 >> $E/repro2/run.log 2>&1
  echo "END $label $(date +%H:%M:%S) rc=$?" >> $E/serialBC.log
  ls -t /Library/Logs/DiagnosticReports/ | head -3 >> $E/serialBC.log
  sleep 10
done
echo DONE-B >> $E/serialBC.log
$E/serialC.sh
