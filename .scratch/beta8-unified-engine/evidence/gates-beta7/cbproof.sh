#!/bin/bash
# usage: cbproof.sh <label> <model> <prompt-file> <devenv> <ctx> <ub> <target_ms> [extra server args]
# Shipped llama-server, one chat request with the prompt, TOSH_MTL_CB_STATS=1; prints max/sum per batch.
B=/Users/sam/firellama/dist/XeonLLM.app/Contents/Resources/bin; O=/Users/sam/firellama/.scratch/beta8-unified-engine/evidence/gates-beta7/out2/cb; mkdir -p $O
label=$1 model=$2 prompt=$3 devenv=$4 ctx=$5 ub=$6 tgt=$7; shift 7
port=18$((RANDOM%800+150))
env $devenv TOSH_FA_AMD=1 TOSH_MTL_CB_STATS=1 TOSH_MTL_CB_TARGET_MS=$tgt perl -e 'alarm 1500; exec @ARGV' $B/llama-server -m $model -ngl 99 -c $ctx -t 12 -fa auto --jinja --ubatch-size $ub --batch-size $ub --host 127.0.0.1 --port $port "$@" > $O/$label.log 2>&1 &
pid=$!
for i in $(seq 1 240); do curl -sf http://127.0.0.1:$port/health >/dev/null && break; kill -0 $pid 2>/dev/null || break; sleep 1; done
python3 - $port "$prompt" > $O/$label.out <<'PY'
import sys,json,http.client,time
port=int(sys.argv[1]); p=open(sys.argv[2]).read()
body={"messages":[{"role":"user","content":p}],"max_tokens":32,"temperature":0}
t=time.time(); c=http.client.HTTPConnection("127.0.0.1",port,timeout=1400); c.request("POST","/v1/chat/completions",json.dumps(body),{"Content-Type":"application/json"}); r=c.getresponse(); d=json.loads(r.read())
m=d["choices"][0]["message"]; print(r.status, round(time.time()-t,1), d.get("timings",{}).get("prompt_per_second"), repr(((m.get("reasoning_content") or "")+"|"+(m.get("content") or ""))[:200]))
PY
kill -INT $pid; wait $pid 2>/dev/null
echo "$label: $(cat $O/$label.out | cut -c1-80) batches=$(grep -c 'cb stats' $O/$label.log) maxmax=$(grep -o 'max=[0-9.]*' $O/$label.log | cut -d= -f2 | sort -n | tail -1) ms timeouts=$(grep -c Timeout $O/$label.log)"
