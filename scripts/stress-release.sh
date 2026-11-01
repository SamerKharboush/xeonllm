#!/bin/bash
# Reproduce the launch the XeonLLM app performs, then drive the engine through the prompt bands
# and the request shapes the release contract lists (section 4).
#
# usage: scripts/stress-release.sh <bin-dir> <model.gguf> [more models...]
#
# It reads the newest app server log's `args:` and `env:` lines, drops the model and draft paths,
# the MCP server list, the web UI and host/port, and starts <bin-dir>/llama-server on 127.0.0.1
# with a free port. It never touches port 8080 or a running app.
set -u

BIN_DIR="${1:-}"; shift || true
if [ -z "$BIN_DIR" ] || [ $# -eq 0 ]; then
    echo "usage: $0 <bin-dir> <model.gguf> [more models...]" >&2
    exit 2
fi
MODELS=("$@")

BIN_DIR="$(cd "$BIN_DIR" && pwd)"
SERVER="$BIN_DIR/llama-server"
[ -x "$SERVER" ] || { echo "no llama-server in $BIN_DIR" >&2; exit 2; }

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-${TMPDIR:-/tmp}/xeonllm-stress-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
# one run at a time per OUT dir: two overlapping runs share the server logs and current.pid
if [ -e "$OUT/.lock" ]; then echo "another stress run holds $OUT/.lock" >&2; exit 3; fi
: > "$OUT/.lock"
trap 'rm -f "$OUT/.lock"' EXIT
TABLES="$OUT/tables"
mkdir -p "$TABLES"

LOGDIR="$HOME/Library/Application Support/XeonLLM/logs"
APPLOG="$(ls -t "$LOGDIR"/server-*.log 2>/dev/null | head -1)"

# --- the app's launch flags ---------------------------------------------------------------
ARGS=()
ENVS=()
if [ -n "$APPLOG" ] && [ -f "$APPLOG" ]; then
    echo "launch flags from: $APPLOG"
    env_line="$(grep -m1 '^ env: ' "$APPLOG" | sed 's/^ env: //')"
    args_line="$(grep -m1 '^ args: ' "$APPLOG" | sed 's/^ args: //')"
    for kv in $env_line; do
        [[ "$kv" == *=* ]] && ENVS+=("$kv")
    done

    # values of the args we drop, so their tokens are not mistaken for flags
    read -r -a raw <<< "$args_line"
    skip_next=0
    for ((i = 0; i < ${#raw[@]}; i++)); do
        a="${raw[$i]}"
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$a" in
            -m|-md|--host|--port|--api-key|--path|--ui-config|--mcp-servers-json|--mcp-agent|-ngld|-ctkd|-ctvd|--spec-type|--tensor-split)
                skip_next=1; continue ;;
            -m=*|-md=*|--host=*|--port=*|--api-key=*) continue ;;
        esac
        # a draft model makes the run non-deterministic and is covered by its own ticket
        ARGS+=("$a")
    done
else
    echo "no app log under '$LOGDIR'; using the flags Sources/Servers/Server.swift builds" >&2
    ARGS=(-ngl 99 -c 32768 -t 10 -fa auto --load-mode none --jinja --no-reasoning-preserve
          --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode tensor
          --tools all --ui-mcp-proxy -n 2048)
    ENVS=(TOSH_FA_AMD=1)
fi

# the app always names both cards; keep whichever the caller wants
ENVS+=("GGML_METAL_DEVICE_LIST=${GGML_METAL_DEVICE_LIST:-0,1}")

PARALLEL=1
for ((i = 0; i < ${#ARGS[@]}; i++)); do
    [ "${ARGS[$i]}" = "--parallel" ] && PARALLEL="${ARGS[$((i+1))]}"
done

free_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

DRIVER="$OUT/drive_cells.py"
cat > "$DRIVER" <<'PY'
import json, sys, threading, http.client, time

HOST, PORT, MODEL, OUT, PARALLEL = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], int(sys.argv[5])
results = []
answers = []

def add(name, status, note, ptok):
    # print each cell as it lands so a stall leaves the finished cells on disk
    print(f"{name}\t{status}\t{note}\t{ptok}", flush=True)

def post(payload, timeout=900):
    c = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    body = json.dumps(payload)
    c.request("POST", "/v1/chat/completions", body, {"Content-Type": "application/json"})
    r = c.getresponse()
    data = r.read()
    c.close()
    return r.status, data

def cell(name, payload, want_tool=False):
    t0 = time.time()
    try:
        status, data = post(payload)
        js = json.loads(data) if data else {}
        if status != 200:
            add(name, "FAIL", f"HTTP {status}: {data[:200]!r}", 0)
            return None
        ch = js.get("choices", [{}])[0]
        msg = ch.get("message", {})
        text = msg.get("content") or msg.get("reasoning_content") or ""
        calls = msg.get("tool_calls") or []
        ptok = js.get("usage", {}).get("prompt_tokens", 0)
        ctok = js.get("usage", {}).get("completion_tokens", 0)
        ok = bool(text.strip()) and (ctok >= 1)
        if want_tool and not calls:
            add(name, "FAIL", "no tool_calls in the answer", ptok)
            return None
        if not ok:
            add(name, "FAIL", f"empty answer (prompt {ptok}, completion {ctok})", ptok)
            return None
        answers.append((name, text[:400].replace("\n", " ")))
        add(name, "PASS", f"prompt_tokens={ptok} completion_tokens={ctok} {time.time()-t0:.1f}s", ptok)
        return js
    except Exception as e:
        add(name, "FAIL", f"{type(e).__name__}: {e}", 0)
        return None

def band(tokens, topic):
    # ~4 chars per token of English prose
    words = ("the quick brown fox jumps over the lazy dog while the compiler waits for the "
             "next token and the gpu finishes its tile " * (tokens // 18 + 2))
    prompt = f"{topic}\n\n{words}\n\nIn one word, what colour is the sky?"
    return {"model": MODEL, "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 64, "temperature": 0.0, "stream": False}

TOPIC = "You are a terse assistant. Read the text and answer the final question."

for t in (16, 300, 450, 520, 1100, 4200, 8300):
    cell(f"band{t}", band(t, TOPIC))

# six turns that reuse the cache
msgs = []
for i in range(6):
    msgs.append({"role": "user", "content": f"Turn {i}: name a colour (one word). " + "filler " * 200})
    cell(f"conv6-turn{i}", {"model": MODEL, "messages": msgs, "max_tokens": 64, "temperature": 0.0})
    msgs.append({"role": "assistant", "content": "blue"})

# a prompt past the cache window, then a small one: the cache must evict and still answer
cell("evict", band(16000, TOPIC))
cell("after-evict", band(32, TOPIC))

# tools
cell("tools", {"model": MODEL,
               "messages": [{"role": "user", "content": "What is the weather in Lisbon? Use the tool."}],
               "tools": [{"type": "function", "function": {
                   "name": "get_weather", "description": "Get the current weather",
                   "parameters": {"type": "object", "properties": {"city": {"type": "string"}},
                                  "required": ["city"]}}}],
               "tool_choice": "auto", "max_tokens": 128, "temperature": 0.0}, want_tool=True)

# two concurrent requests
if PARALLEL >= 2:
    out = []
    def one(i):
        out.append((i, post(band(220, TOPIC))[0]))
    ts = [threading.Thread(target=one, args=(i,)) for i in range(2)]
    [t.start() for t in ts]; [t.join() for t in ts]
    ok = len(out) == 2 and all(s == 200 for _, s in out)
    add("parallel2", "PASS" if ok else "FAIL", f"statuses={out}", 0)
else:
    add("parallel2", "SKIP", f"--parallel {PARALLEL} does not allow it", 0)

# a cancelled stream, then a new request
try:
    c = http.client.HTTPConnection(HOST, PORT, timeout=30)
    c.request("POST", "/v1/chat/completions",
              json.dumps({"model": MODEL, "messages": [{"role": "user", "content": "Write a very long essay about the sea."}],
                          "max_tokens": 4096, "stream": True}),
              {"Content-Type": "application/json"})
    r = c.getresponse()
    r.read(64)
    c.close()
    add("cancel-stream", "PASS", "stream closed after 64 bytes", 0)
except Exception as e:
    add("cancel-stream", "FAIL", f"{type(e).__name__}: {e}", 0)
cell("after-cancel", band(64, TOPIC))

results = []  # each cell already printed; keep the list shape for the caller

with open(f"{OUT}/answers.txt", "w") as f:
    for name, text in answers:
        f.write(f"== {name}\n{text}\n\n")
PY

# llama-server on this fork can hang in its shutdown path ("cleaning up before exit..." never
# returns), so a plain SIGTERM leaves the process holding GPU memory. Escalate to SIGKILL.
kill_server() {
    local pid="$1"
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null
    for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || return 0; sleep 1; done
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 0
}

# --- run one server with a given extra flag set -------------------------------------------
run_server() {
    local model="$1" label="$2"; shift 2
    local port; port="$(free_port)"
    local log="$OUT/$(basename "$model" .gguf)-$label.server.log"
    local runargs=("${ARGS[@]}" -m "$model" --host 127.0.0.1 --port "$port")
    if [ $# -gt 0 ]; then runargs+=("$@"); fi
    echo "== $(basename "$model") [$label] port $port"
    ( cd "$OUT" && env "${ENVS[@]}" "$SERVER" "${runargs[@]}" > "$log" 2>&1 & echo $! > "$OUT/current.pid" )
    local pid; pid="$(cat "$OUT/current.pid")"
    local up=0
    for _ in $(seq 1 240); do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        if curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1; then up=1; break; fi
        sleep 1
    done
    if [ "$up" != 1 ]; then
        echo -e "$(basename "$model")\t$label\tFAIL\tserver did not start; see $log" >> "$TABLES/raw.tsv"
        kill_server "$pid"
        sleep 20
        return 1
    fi

    python3 "$DRIVER" 127.0.0.1 "$port" "$model" "$OUT" "$PARALLEL" > "$OUT/$(basename "$model" .gguf)-$label.cells.tsv" 2>&1

    kill_server "$pid"
    local bad
    bad="$(grep -nE 'kernel not found|exited with code|GGML_ASSERT|GGML_ABORT|failed to create pipeline' "$log" | head -3)"
    while IFS=$'\t' read -r cell status note ptok; do
        local verdict="$status" why="$note"
        if [ -n "$bad" ] && [ "$status" = "PASS" ]; then verdict="FAIL"; why="log: ${bad%%$'\n'*}"; fi
        echo -e "$(basename "$model")\t$label\t$cell\t$verdict\t$why\t$ptok" >> "$TABLES/raw.tsv"
    done < "$OUT/$(basename "$model" .gguf)-$label.cells.tsv"
    if [ -n "$bad" ]; then
        echo -e "$(basename "$model")\t$label\t(log)\tFAIL\t${bad//$'\n'/ | }" >> "$TABLES/raw.tsv"
    fi
    sleep 20
}

# --- the matrix ---------------------------------------------------------------------------
: > "$TABLES/raw.tsv"
HEADER=$'\tmodel\tsplit\tcell\tverdict\tdetail\tprompt_tokens'
echo -e "model\tsplit\tcell\tverdict\tdetail\tprompt_tokens" > "$TABLES/stress.tsv"

for model in "${MODELS[@]}"; do
    [ -f "$model" ] || { echo "missing model: $model" >&2; continue; }
    for mode in ${MODES:-tensor layer ngl0}; do
        case "$mode" in
            tensor) run_server "$model" "tensor" ;;
            layer)  run_server "$model" "layer" --split-mode layer ;;
            ngl0)   run_server "$model" "ngl0" -ngl 0 ;;
            *)      echo "unknown mode: $mode" >&2 ;;
        esac
    done
done

cat "$TABLES/raw.tsv" >> "$TABLES/stress.tsv"
echo "results: $TABLES/stress.tsv"
echo "logs:    $OUT"
