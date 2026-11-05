#!/bin/bash
D=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/09
F="/Users/sam/models/Nanbeige4.3-33B-GGUF/Nanbeige4.3-33B-Q8_0.gguf"
for r in 1 2 3 4 5; do echo "## rep $r"; $D/bin/nvmeread "$F" $(( (r-1)*5 )) 4 1000 $r || exit 1; done
echo "### done"
