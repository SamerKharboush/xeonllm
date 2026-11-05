#!/bin/bash
# beta8 tickets 09 (read ceiling, host copy) and 07 (shared-buffer read), both cards, N=5, alternating.
D=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/09
for r in 1 2 3 4 5; do for c in 0 1; do
  echo "## rep $r card $c private"; $D/bin/readceiling $c 1024 1.5 private || exit 1
  echo "## rep $r card $c shared";  $D/bin/readceiling $c 1024 1.5 shared  || exit 1
  echo "## rep $r card $c hostcopy"; $D/bin/hostcopy $c 1024 64 || exit 1
done; done
echo "### done"
