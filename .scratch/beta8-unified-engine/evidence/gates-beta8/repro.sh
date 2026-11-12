#!/bin/bash
# usage: repro.sh <label> [extra server args...]   env passes through (B = bin dir, LOGDIR)
# Qwen3-14B Q4_K_M layer split over both cards at the app's launch, one ~5.4k-token prompt.
B=${B:-/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin}
L=${LOGDIR:-$(dirname "$0")/out}; mkdir -p $L
label=$1; shift
port=18$((RANDOM%900+100))
GGML_METAL_DEVICE_LIST=0,1 TOSH_FA_AMD=1 $B/llama-server -m /Users/sam/models/Qwen3-14B-Q4_K_M.gguf -ngl 99 -c 32768 -t 10 -fa auto --jinja --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode layer --host 127.0.0.1 --port $port "$@" > $L/repro-$label.log 2>&1 &
pid=$!
for i in $(seq 1 240); do curl -sf http://127.0.0.1:$port/health >/dev/null && break; sleep 1; done
python3 - $port <<'PY' > $L/repro-$label.out 2>&1
import sys, json, http.client, time
port=int(sys.argv[1])
words=("the quick brown fox jumps over the lazy dog while the compiler waits for the next token and the gpu finishes its tile " * (4200//18+2))
p={"messages":[{"role":"user","content":f"Why is the sky blue?\n\n{words}\n\nIn one word, what colour is the sky?"}],"max_tokens":64,"temperature":0.0}
t=time.time(); c=http.client.HTTPConnection("127.0.0.1",port,timeout=3600); c.request("POST","/v1/chat/completions",json.dumps(p),{"Content-Type":"application/json"}); r=c.getresponse(); d=r.read()
print(r.status, round(time.time()-t,1), d[:300])
try:
    m=json.loads(d)["choices"][0]["message"]; txt=(m.get("content") or "")+(m.get("reasoning_content") or "")
except Exception as e:
    txt=""
bad = (not txt.strip()) or txt.count("@") > len(txt)//2
print("TEXT BAD" if bad else "text ok", repr(txt[:60]))
PY
kill $pid; for i in $(seq 1 15); do kill -0 $pid 2>/dev/null || break; sleep 1; done; kill -9 $pid 2>/dev/null
echo "$label: $(head -1 $L/repro-$label.out | cut -c1-120) timeouts=$(grep -c Timeout $L/repro-$label.log) $(tail -1 $L/repro-$label.out | cut -c1-80)"
sleep 10
