#!/bin/bash
# usage: srv.sh <label> <outdir> <request.json> <env assignments...> -- <llama-server args...>
# Shipped llama-server (alarm 1500 s), waits for /health, sends one POST /v1/chat/completions,
# saves <label>.json (raw), <label>.log (server log), <label>.txt (reasoning|content), stops it.
B=/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin
label=$1 O=$2 req=$3; shift 3; mkdir -p $O
envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
port=18$((RANDOM%800+150))
env "${envs[@]}" perl -e 'alarm 1500; exec @ARGV' $B/llama-server --host 127.0.0.1 --port $port "$@" > $O/$label.log 2>&1 &
pid=$!
for i in $(seq 1 600); do curl -sf http://127.0.0.1:$port/health >/dev/null && break; kill -0 $pid 2>/dev/null || break; sleep 1; done
curl -s --max-time 1400 -H 'Content-Type: application/json' -d @"$req" http://127.0.0.1:$port/v1/chat/completions > $O/$label.json
kill -INT $pid 2>/dev/null; for i in $(seq 1 20); do kill -0 $pid 2>/dev/null || break; sleep 1; done; kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null
python3 - $O/$label.json $O/$label.txt <<'PY'
import sys,json
try:
    d=json.load(open(sys.argv[1])); m=d["choices"][0]["message"]
    t=(m.get("reasoning_content") or "")+"|"+(m.get("content") or "")
except Exception as e:
    t="NO-ANSWER "+repr(e)
open(sys.argv[2],"w").write(t)
print(repr(t[:120]))
PY
sleep 5
