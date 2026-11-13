#!/bin/bash
# Release contract section 3 (and the section 2 proofs) on the shipped beta 8 binaries.
# Adapted from gates-beta7/gates.sh: every GPU program under an alarm, a crash-report check after
# every GPU program (stops the script), no model >= 5905580032 bytes on one card (Nemotron
# 6180446208 is out of the one-card proofs), FA also with TOSH_FA_AMD_DISABLE=1 (TOSH_FA_AMD=1 is
# inert: the AMD kernel is on by default on 64-lane cards), and the metal/0083 + metal/0084 proofs.
cd /Users/sam/firellama
G=$PWD/.scratch/beta8-unified-engine/evidence/gates-beta8
B=dist/XeonLLM.app/Contents/Resources/bin; O=$G/${GATES_OUT:-out}; mkdir -p $O
M=/Users/sam/models
SECTIONS=${GATES_SECTIONS:-identity,ops,coverage,prefill,preflight,engine,proofs,proofs8,avx,repro}
want() { case ",$SECTIONS," in *",$1,"*) return 0;; *) return 1;; esac; }
al() { local t=$1; shift; perl -e 'alarm shift; exec @ARGV' "$t" "$@"; }
# Crash check by NAME: the system prunes old reports, so a falling count is not a crash.
CRL=$(mktemp); ls /Library/Logs/DiagnosticReports/ | grep -E 'panic|watchdog|gpuRestart' | sort > $CRL
chk() {
    local new; new=$(ls /Library/Logs/DiagnosticReports/ | grep -E 'panic|watchdog|gpuRestart' | sort | comm -13 $CRL -)
    if [ -n "$new" ]; then echo "NEW CRASH REPORT after $1: $(echo $new | tr '\n' ' ') - STOP"; exit 9; fi
}
echo "DiagnosticReports at start: $(ls -t /Library/Logs/DiagnosticReports/ | head -3 | tr '\n' ' ')"
date
if want identity; then
echo "== identity"
shasum -a 256 $B/llama-server $B/llama-bench $B/test-backend-ops | cut -c1-16
$B/llama-server --version 2>&1 | head -3
echo "embedded version strings: $(strings $B/llama-server | grep -Fxc "$(cat VERSION)")"
echo "VERSION $(cat VERSION)"
( sed -n 1,176p tools/ab.sh > $O/ab-fns.sh; source $O/ab-fns.sh; assert_artifact $B/llama-server bundle )
fi
if want ops; then
echo "== 3.1 every op"
for c in 0 1; do
  GGML_METAL_DEVICE_INDEX=$c al 3000 $B/test-backend-ops -b MTL0 > $O/all-c$c.log 2>&1
  echo "card $c ALL rc=$?: $(grep 'tests passed' $O/all-c$c.log | tail -1) FAIL=$(grep -c '\bFAIL\b' $O/all-c$c.log)"; chk ops-all-c$c
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 al 1800 $B/test-backend-ops -b MTL0 -o FLASH_ATTN_EXT > $O/fa-c$c.log 2>&1
  echo "card $c FA TOSH_FA_AMD=1 rc=$?: $(grep 'tests passed' $O/fa-c$c.log | tail -1) FAIL=$(grep -c '\bFAIL\b' $O/fa-c$c.log)"; chk ops-fa-c$c
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD_DISABLE=1 al 1800 $B/test-backend-ops -b MTL0 -o FLASH_ATTN_EXT > $O/fa-off-c$c.log 2>&1
  echo "card $c FA TOSH_FA_AMD_DISABLE=1 rc=$?: $(grep 'tests passed' $O/fa-off-c$c.log | tail -1) FAIL=$(grep -c '\bFAIL\b' $O/fa-off-c$c.log)"; chk ops-fa-off-c$c
done
fi
if want coverage; then
echo "== 3.2 kernel coverage"
scripts/check-kernel-coverage.sh $B 2>&1 | tail -4
fi
if want prefill; then
echo "== 3.3 prefill bands"
# Per-card budget 5905580032 bytes (6.44 GB working set minus 512 MiB). At or above it a model
# runs only on both cards (-sm layer and -sm tensor), never on one card.
ONECARD=5905580032
PBANDS=16,128,256,448,512,1024,2048
for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K Qwen3-8B-Q4_K_M Qwen3-14B-Q4_K_M Nemotron-3.5-Bolt-E4B-Q4_K_M LFM3-1.7B-F16 Ternary-Bonsai-2-27B-PQ2_0 Underdog-Saluki-27B-1.0-IQ2-mix; do
  sz=$(stat -L -f %z $M/$m.gguf 2>/dev/null)
  if [ -z "$sz" ]; then echo "$m missing at $M/$m.gguf"; continue; fi
  if [ "$sz" -ge "$ONECARD" ]; then
    for sm in layer tensor; do
      GGML_METAL_DEVICE_LIST=0,1 al 1800 $B/llama-bench -m $M/$m.gguf -ngl 99 -sm $sm -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-$m-both-$sm.csv 2> $O/pp-$m-both-$sm.err
      rc=$?
      note=$(grep -m1 -E 'kernel not found|error|unknown model' $O/pp-$m-both-$sm.err | cut -c1-120)
      if [ "$sm" = tensor ] && [ "$rc" = 86 ] && grep -q 'cannot be tensor-split' $O/pp-$m-both-$sm.err; then note="handled (exit 86)"; fi
      echo "both cards 0,1 -sm $sm $m ($sz bytes, over one card) rc=$rc rows=$(($(wc -l < $O/pp-$m-both-$sm.csv)-1)) $note"
      chk pp-$m-$sm; sleep 3
    done
  else
    for c in 0 1; do
      GGML_METAL_DEVICE_INDEX=$c al 1800 $B/llama-bench -m $M/$m.gguf -ngl 99 -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-$m-c$c.csv 2> $O/pp-$m-c$c.err
      rc=$?; echo "card $c $m ($sz bytes, fits one card) rc=$rc rows=$(($(wc -l < $O/pp-$m-c$c.csv)-1)) $(grep -m1 -E 'kernel not found|error|unknown model' $O/pp-$m-c$c.err | cut -c1-120)"
      chk pp-$m-c$c; sleep 3
    done
  fi
done
al 3000 $B/llama-bench -m $M/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf -ngl 0 -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-35b-host.csv 2> $O/pp-35b-host.err
echo "35B host (-ngl 0) rc=$? rows=$(($(wc -l < $O/pp-35b-host.csv)-1))"; chk pp-35b-host
fi
if want preflight; then
echo "== 3.4 preflight"
al 1800 tools/ab.sh --baseline $B/llama-server --model $M/Qwen3-0.6B-Q8_0.gguf --split layer --preflight-only > $O/preflight.log 2>&1; echo "preflight rc=$?"; grep -E 'preflight\[' $O/preflight.log | head -8; chk preflight
fi
if want engine; then
echo "== 3.5 test-engine"
LLAMA_SERVER_BIN_PATH=$PWD/$B/llama-server al 3600 scripts/test-engine.sh > $O/test-engine.log 2>&1; echo "test-engine rc=$?"; tail -3 $O/test-engine.log; chk test-engine
fi
if want proofs; then
echo "== section 2 proofs (wave64 lines, rows8 / full-tg controls; card 1, models under one card)"
for c in 0 1; do grep -hE "SIMD-group width = 64 \(|wave64 decode ON|aligned mat-vec reads ON" $O/all-c$c.log | sort -u | sed "s/^/card $c: /"; done
for e in X TOSH_MV_ROWS8_DISABLE TOSH_FULL_TG_DISABLE; do for m in Qwen3-4B-Q4_K_M Qwen3-0.6B-Q8_0; do
  al 900 env $e=1 GGML_METAL_DEVICE_INDEX=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -p 0 -n 128 -r 5 -fa 1 -o csv 2>/dev/null | tail -1 | awk -F, -v e=$e -v m=$m '{print e " " m " tg128 " $(NF-1) " sd " $NF}'; chk proofs-$e-$m; sleep 5; done; done
fi
if want proofs8; then
echo "== metal/0083 decomposed prefill on 64-lane cards (card 1, Qwen3-4B-Q4_K_M, -ub 128)"
for arm in new w64; do for p in 1 2; do
  if [ $arm = w64 ]; then X=TOSH_FA_PF_W64=1; else X=XEONLLM_NOOP=1; fi
  al 1800 env $X GGML_METAL_DEVICE_INDEX=1 $B/llama-bench -m $M/Qwen3-4B-Q4_K_M.gguf -ngl 99 -fa 1 -ub 128 -p 512 -n 128 -d 6144 -r 3 -o csv > $O/p83-$arm-p$p.csv 2> $O/p83-$arm-p$p.err
  echo "0083 $arm process $p rc=$?"; awk -F, 'NR>1{print "  " $(NF-3) " " $(NF-2) " -> " $(NF-1) " sd " $NF}' $O/p83-$arm-p$p.csv; chk p83-$arm-p$p; sleep 5
done; done
python3 - $O/req83.json <<'PY'
import json,sys
p=open("/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/18/prompt6k.txt").read()
json.dump({"messages":[{"role":"user","content":p}],"max_tokens":64,"temperature":0.0,"seed":1},open(sys.argv[1],"w"))
PY
for arm in new w64; do
  if [ $arm = w64 ]; then X=TOSH_FA_PF_W64=1; else X=XEONLLM_NOOP=1; fi
  echo "0083 text $arm: $($G/srv.sh t83-$arm $O $O/req83.json $X GGML_METAL_DEVICE_INDEX=1 -- -m $M/Qwen3-4B-Q4_K_M.gguf -ngl 99 -c 8192 -ub 128 -b 2048 -fa on -t 12 --jinja --parallel 1 --cache-ram 0)"; chk t83-$arm
done
cmp $O/t83-new.txt $O/t83-w64.txt && echo "0083 text identical" || echo "0083 text DIFFERS"
echo "== metal/0084 gated-delta-net fusion off across several cards (dense qwen35 27B Q6_K, -ngl 12)"
M27=$M/Qwen3.6-27B-Heretic-Uncensored-FINETUNE-NEO-CODE-Di-IMatrix-MAX-GGUF/Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf
echo '{"messages":[{"role":"user","content":"Explain what a binary search tree is."}],"max_tokens":64,"temperature":0.0,"seed":1}' > $O/req84.json
A84="-m $M27 -ngl 12 -c 4096 -ub 128 -b 512 -t 12 -fa on --jinja --parallel 1 --cache-ram 0 -v"
echo "0084 one12: $($G/srv.sh t84-one12 $O $O/req84.json GGML_METAL_DEVICE_INDEX=1 -- $A84)"; chk t84-one12
echo "0084 twocard12: $($G/srv.sh t84-two12 $O $O/req84.json GGML_METAL_DEVICE_LIST=0,1 -- $A84 --split-mode layer)"; chk t84-two12
echo "0084 twocard12 MULTI=1 (control): $($G/srv.sh t84-two12-multi $O $O/req84.json GGML_METAL_DEVICE_LIST=0,1 TOSH_GDN_STATE_FUSION_MULTI=1 -- $A84 --split-mode layer)"; chk t84-two12-multi
cmp $O/t84-one12.txt $O/t84-two12.txt && echo "0084 twocard12 identical to one12" || echo "0084 twocard12 DIFFERS from one12"
cmp $O/t84-one12.txt $O/t84-two12-multi.txt && echo "0084 control identical (control did not take effect)" || echo "0084 control differs (expected)"
for t in one12 two12 two12-multi; do echo "kernels $t: $(grep -oE 'gated_delta_net[A-Za-z0-9_=]*rows=[01]_fold=[01]' $O/t84-$t.log | sort -u | tr '\n' ' ')"; done
fi
if want avx; then
echo "== AVX2/FMA mnemonics"
for f in $B/*; do [ -x "$f" ] && file "$f" | grep -q Mach-O && echo "$(basename $f): $(otool -tv "$f" 2>/dev/null | grep -cE '\b(vfmadd|vfmsub|vfnmadd|vpbroadcast[bwdq]|vpermd|vpermq|vperm2i128|vinserti128|vextracti128|vpgatherdd|vgatherdps|vpsllvd|vpsrlvd)')"; done
fi
if want repro; then
echo "== 0078 on the shipped engine (14B layer split over both cards, ~5.4k prompt)"
al 1800 $G/repro.sh ship; chk repro
fi
pgrep -fl "firellama.*llama-server" || echo "no servers of ours"
echo "DiagnosticReports at end: $(ls -t /Library/Logs/DiagnosticReports/ | head -3 | tr '\n' ' ')"
date
echo GATES DONE
