#!/bin/sh
# run.sh <T|X> <modelkey> <label> <promptfile> <serverlog> <outfile>
# starts one llama-server in foreground under an alarm, waits /health, sends one request, kills it, waits until gone, checks DiagnosticReports.
set -u
E=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/compare/machine
BIN=$1
case "$BIN" in
  T) B=/Applications/ToshLLM.app/Contents/Resources/bin/llama-server ;;
  X) B=/Applications/XeonLLM.app/Contents/Resources/bin/llama-server ;;
  *) echo "bad bin $BIN" >&2; exit 2 ;;
esac
KEY=$2; LABEL=$3; PF=$4; LOG=$5; OUT=$6; EXENV=${7:-}

case "$KEY" in
  m1)
    ENV_PREFIX="TOSH_AUTO_KV=auto ${M1FA:-TOSH_FA_AMD=1} GGML_METAL_DEVICE_LIST=0,1"
    ARGS="-m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf -ngl 99 -c 16384 -t 12 -fa auto --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode tensor -n 2048 --host 127.0.0.1 --port 18130"
    TIMEOUT=1800 ;;
  m2)
    ENV_PREFIX="TOSH_FA_AMD=1 GGML_METAL_DEVICE_LIST=1"
    ARGS="-m /Users/sam/models/gemma-4-12B-coder-fable5-composer2.5-v1-GGUF/gemma4-coding-Q8_0.gguf -ngl 0 -c 8192 -t 12 -fa auto --load-mode none --jinja --metrics --cache-ram 0 --parallel 1 -n 2048 --host 127.0.0.1 --port 18130"
    TIMEOUT=1800 ;;
  m3)
    ENV_PREFIX="TOSH_AUTO_KV=auto ${M1FA:-TOSH_FA_AMD=1} GGML_METAL_DEVICE_LIST=0,1"
    ARGS="-m /Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf -ngl 99 -c 32768 -t 12 -fa 1 --dynamic-moe on --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 -n 2048 --host 127.0.0.1 --port 18130"
    TIMEOUT=1800 ;;
esac

if curl -s -m 2 -o /dev/null http://127.0.0.1:18130/health; then echo "port 18130 busy, aborting" >&2; exit 4; fi
if ps -Ao command | grep -i llama-server | grep -v grep | grep -v '/Users/sam/llama.cpp/' | grep -qv "$$"; then echo "another llama-server is running, aborting" >&2; exit 3; fi

env $ENV_PREFIX $EXENV perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" "$B" $ARGS >"$LOG" 2>&1 &
PID=$!
echo "$PID" > "$LOG.pid"

i=0
while [ $i -lt 60 ]; do
  if ! kill -0 $PID 2>/dev/null; then echo "server exited early" >&2; tail -20 "$LOG" >&2; exit 5; fi
  if curl -s -m 5 http://127.0.0.1:18130/health | grep -q '"status"'; then break; fi
  i=$((i+1)); sleep 10
done
if [ $i -ge 60 ]; then echo "health timeout" >&2; kill $PID; wait $PID 2>/dev/null; exit 6; fi

python3 - "$PF" "$OUT" <<'PY'
import json,sys,urllib.request
pf,out=sys.argv[1],sys.argv[2]
text=open(pf,encoding='utf-8').read()
body=json.dumps({"messages":[{"role":"user","content":text}],"max_tokens":128,"temperature":0,"cache_prompt":False}).encode()
req=urllib.request.Request("http://127.0.0.1:18130/v1/chat/completions",data=body,headers={"Content-Type":"application/json"})
with urllib.request.urlopen(req,timeout=1700) as r:
    data=r.read()
open(out,'wb').write(data)
json.loads(data)
PY
RC=$?
kill $PID 2>/dev/null
wait $PID 2>/dev/null
sleep 2
if ps -Ao pid,ppid,command | awk -v p=$$ '$2!=p && $2!=1 && /llama-server/ {print}' | grep -q .; then echo "another llama-server is running, aborting" >&2; exit 3; fi
ls /Library/Logs/DiagnosticReports/ | sort > $E/diag-now.txt
if comm -13 $E/diag-first.txt $E/diag-now.txt | grep -E 'panic|watchdog|gpuRestart'; then echo "PANIC DETECTED" >&2; exit 9; fi
echo "OK $LABEL rc=$RC $(date)"