#!/bin/bash
# Release contract section 3 (and the section 2 proofs) on the shipped beta.6 binaries.
cd /Users/sam/firellama
B=dist/XeonLLM.app/Contents/Resources/bin; O=$(dirname "$0")/out; mkdir -p $O
M=/Users/sam/models
# GATES_SECTIONS: comma list of {identity,ops,coverage,prefill,preflight,engine,proofs,avx,repro}
# to run; default all. A rerun of a partially passed gate skips what already passed, e.g.
# GATES_SECTIONS=prefill,preflight,engine,proofs,avx,repro
SECTIONS=${GATES_SECTIONS:-identity,ops,coverage,prefill,preflight,engine,proofs,avx,repro}
want() { case ",$SECTIONS," in *",$1,"*) return 0;; *) return 1;; esac; }
if want identity; then
echo "== identity"
shasum -a 256 $B/llama-server $B/llama-bench $B/test-backend-ops | cut -c1-16
$B/llama-server --version 2>&1 | head -3
for f in llama-server llama-bench; do echo "$f banner: $(strings $B/$f | grep -m1 -o 'XeonLLM engine.*')"; done
echo "VERSION $(cat VERSION)"
( sed -n 1,176p tools/ab.sh > $O/ab-fns.sh; source $O/ab-fns.sh; assert_artifact $B/llama-server bundle )
fi
if want ops; then
echo "== 3.1 every op"
for c in 0 1; do
  GGML_METAL_DEVICE_INDEX=$c $B/test-backend-ops -b MTL0 > $O/all-c$c.log 2>&1
  echo "card $c ALL: $(grep 'tests passed' $O/all-c$c.log | tail -1) FAIL=$(grep -c '\bFAIL\b' $O/all-c$c.log)"
  GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $B/test-backend-ops -b MTL0 -o FLASH_ATTN_EXT > $O/fa-c$c.log 2>&1
  echo "card $c FA TOSH_FA_AMD=1: $(grep 'tests passed' $O/fa-c$c.log | tail -1) FAIL=$(grep -c '\bFAIL\b' $O/fa-c$c.log)"
done
fi
if want coverage; then
echo "== 3.2 kernel coverage"
scripts/check-kernel-coverage.sh $B 2>&1 | tail -4
fi
if want prefill; then
echo "== 3.3 prefill bands"
# Per-card budget: recommendedMaxWorkingSetSize 6442450944 (6442.45 MB) minus 512 MiB
# (536870912) for KV and compute = 5905580032 bytes. A model at or above that never runs
# on one card: card 0 drives the display and a paged card stalls WindowServer until macOS
# panics (2026-11-03, Ternary-Bonsai-2-27B-PQ2_0 at -p 1024 on card 0, twice). It runs on
# both cards, -sm layer and -sm tensor, as the app places it.
ONECARD=5905580032
PBANDS=16,128,256,448,512,1024,2048
for m in Qwen3-0.6B-Q8_0 Qwen3-4B-Q4_K_M Qwen3-4B-Q6_K Qwen3-8B-Q4_K_M Qwen3-14B-Q4_K_M Nemotron-3.5-Bolt-E4B-Q4_K_M LFM3-1.7B-F16 Ternary-Bonsai-2-27B-PQ2_0 Underdog-Saluki-27B-1.0-IQ2-mix; do
  sz=$(stat -f %z $M/$m.gguf 2>/dev/null)
  if [ -z "$sz" ]; then echo "$m missing at $M/$m.gguf"; continue; fi
  if [ "$sz" -ge "$ONECARD" ]; then
    for sm in layer tensor; do
      GGML_METAL_DEVICE_LIST=0,1 TOSH_FA_AMD=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -sm $sm -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-$m-both-$sm.csv 2> $O/pp-$m-both-$sm.err
      rc=$?
      note=$(grep -m1 -E 'kernel not found|error|unknown model' $O/pp-$m-both-$sm.err | cut -c1-120)
      if [ "$sm" = tensor ] && [ "$rc" = 86 ] && grep -q 'cannot be tensor-split' $O/pp-$m-both-$sm.err; then note="handled (exit 86)"; fi
      echo "both cards 0,1 -sm $sm $m ($sz bytes, over one card) rc=$rc rows=$(($(wc -l < $O/pp-$m-both-$sm.csv)-1)) $note"
      sleep 3
    done
  else
    for c in 0 1; do
      GGML_METAL_DEVICE_INDEX=$c TOSH_FA_AMD=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-$m-c$c.csv 2> $O/pp-$m-c$c.err
      rc=$?; echo "card $c $m ($sz bytes, fits one card) rc=$rc rows=$(($(wc -l < $O/pp-$m-c$c.csv)-1)) $(grep -m1 -E 'kernel not found|error|unknown model' $O/pp-$m-c$c.err | cut -c1-120)"
      sleep 3
    done
  fi
done
TOSH_FA_AMD=1 $B/llama-bench -m $M/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf -ngl 0 -fa 1 -p $PBANDS -n 0 -r 1 -o csv > $O/pp-35b-host.csv 2> $O/pp-35b-host.err
echo "35B host (-ngl 0) rc=$? rows=$(($(wc -l < $O/pp-35b-host.csv)-1))"
fi
if want preflight; then
echo "== 3.4 preflight"
tools/ab.sh --baseline $B/llama-server --model $M/Qwen3-0.6B-Q8_0.gguf --split layer --preflight-only > $O/preflight.log 2>&1; echo "preflight rc=$?"; grep -E 'preflight\[' $O/preflight.log | head -8
fi
if want engine; then
echo "== 3.5 test-engine"
LLAMA_SERVER_BIN_PATH=$PWD/$B/llama-server scripts/test-engine.sh > $O/test-engine.log 2>&1; echo "test-engine rc=$?"; tail -3 $O/test-engine.log
fi
if want proofs; then
echo "== section 2 proofs"
for c in 0 1; do grep -hE "SIMD-group width = 64 \(|wave64 decode ON|aligned mat-vec reads ON" $O/all-c$c.log | sort -u | sed "s/^/card $c: /"; done
for e in X TOSH_MV_ROWS8_DISABLE TOSH_FULL_TG_DISABLE; do for m in Qwen3-4B-Q4_K_M Nemotron-3.5-Bolt-E4B-Q4_K_M; do
  env $e=1 GGML_METAL_DEVICE_INDEX=1 $B/llama-bench -m $M/$m.gguf -ngl 99 -p 0 -n 128 -r 5 -fa 1 -o csv 2>/dev/null | tail -1 | awk -F, -v e=$e -v m=$m '{print e " " m " tg128 " $(NF-1) " sd " $NF}'; sleep 5; done; done
fi
if want avx; then
echo "== AVX2/FMA mnemonics"
for f in $B/*; do [ -x "$f" ] && file "$f" | grep -q Mach-O && echo "$(basename $f): $(otool -tv "$f" 2>/dev/null | grep -cE '\b(vfmadd|vfmsub|vfnmadd|vpbroadcast[bwdq]|vpermd|vpermq|vperm2i128|vinserti128|vextracti128|vpgatherdd|vgatherdps|vpsllvd|vpsrlvd)')"; done
fi
if want repro; then
echo "== 0078 on the shipped engine"
$(dirname "$0")/repro.sh ship
TOSH_MTL_PREFILL_CB=1 $(dirname "$0")/repro.sh shipctl
fi
pgrep -fl "firellama.*llama-server" || echo "no servers of ours"
echo GATES DONE
