#!/bin/bash
# Reproduce the launch the XeonLLM app performs, then drive the engine through the prompt bands
# and the request shapes the release contract lists (section 4).
#
# usage: scripts/stress-release.sh <bin-dir> <model.gguf> [more models...]
#
# It reads the newest app server log's `args:` and `env:` lines (or the log named by APPLOG),
# drops the model and draft paths, the MCP server list, the web UI and host/port, and starts
# <bin-dir>/llama-server on 127.0.0.1 with a free port. It never touches port 8080 or a running app.
#
# MODES (default "tensor layer ngl0"): tensor = the app's flags as logged; layer adds
# --split-mode layer; ngl0 adds -ngl 0; draft adds the DFlash drafter the app would load, the
# file <model stem>.dflash.gguf beside the model (a model without one gets a SKIP row, as the app
# launches it without a drafter), with the app's flags (-ngld DRAFT_NGLD, default 99), -lv 4 and
# DRAFT_EXTRA (e.g. "--split-mode layer", the app's fallback after exit 86), and checks the log
# for where the drafter's borrowed head went. CELL_TIMEOUT (default 900 s) bounds each request.
# Each mode gets the env the app builds for it: the tensor-only switches (TOSH_MGPU_EVENTS,
# _PEER, _TENSOR_GROUP, TOSH_MIRROR_OUTPUT_HEAD) only on a tensor split, no card list at -ngl 0.
# NGL0_CELLS (e.g. "band16 band300 band1100") limits the ngl0 mode to those cells; CELLS does
# the same for every other mode (for a repro of one failing cell).
# After a model's modes, band16, band300 and band1100 of every mode are compared byte for byte
# with the tensor mode (identical-vs-tensor, gated), with the ngl0 mode (identical-vs-ngl0,
# reported as DIFFERS, not gated: Metal and the CPU sum in a different order), and, when PREV_OUT
# names the previous release's $OUT, with the same mode there (identical-vs-previous, gated).
# Answers are kept in full under $OUT.
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
APPLOG="${APPLOG:-$(ls -t "$LOGDIR"/server-*.log 2>/dev/null | head -1)}"

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

# A model above one card's working set (6442450944 bytes less 512 MiB for KV and compute) never
# runs on one card: card 0 drives the display, and a paged card stalls WindowServer until macOS
# panics and reboots (2026-11-03, a 7.2 GB model on card 0, twice). Refuse before starting.
ONECARD=5905580032

# True (0) when the arguments keep experts or tensors in RAM: --dynamic-moe on, --cpu-moe/-cmoe,
# --n-cpu-moe N with N > 0 (the app passes --n-cpu-moe 0 on a plain card launch), -ot ...=CPU.
offloads() {
    local i
    local -a v=("$@")
    for ((i = 0; i < ${#v[@]}; i++)); do
        case "${v[$i]}" in
            --cpu-moe|-cmoe) return 0 ;;
            --dynamic-moe) [ "${v[$((i+1))]}" != off ] && return 0 ;;
            --n-cpu-moe|-ncmoe) [ "${v[$((i+1))]:-0}" -gt 0 ] 2>/dev/null && return 0 ;;
            -ot|--override-tensor) [[ "${v[$((i+1))]}" == *=CPU* ]] && return 0 ;;
        esac
    done
    return 1
}

one_card=0
for kv in "${ENVS[@]}"; do
    case "$kv" in
        GGML_METAL_DEVICE_INDEX=*) one_card=1 ;;
        GGML_METAL_DEVICE_LIST=*) [[ "${kv#*=}" == *,* ]] || one_card=1 ;;
    esac
done
# The app's expert tier is the one exception: one card holds attention and the hot experts, which
# its plan sizes to the card, and the CPU computes the rest (--dynamic-moe, or an explicit offload).
offloads "${ARGS[@]}" && one_card=0
if [ "$one_card" = 1 ]; then
    for m in "${MODELS[@]}"; do
        sz=$(stat -L -f %z "$m" 2>/dev/null || echo 0)   # -L: a link is sized as its target
        if [ "$sz" -ge "$ONECARD" ]; then
            echo "refusing: $m is $sz bytes, above one card's $ONECARD, and the env names one card" >&2
            exit 3
        fi
    done
fi

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
RUN = sys.argv[6]  # <model stem>-<label>, names this run's answer files
TIMEOUT = int(sys.argv[7])  # seconds per request; -ngl 0 on a large model prefills slowly
ONLY = sys.argv[8].split()  # run only these cells (empty: all)

def save():
    # after every cell, so a run that is stopped keeps the answers it finished
    with open(f"{OUT}/{RUN}.answers.json", "w") as f:
        json.dump(dict(answers), f, ensure_ascii=False, indent=1)
    with open(f"{OUT}/{RUN}.answers.txt", "w") as f:
        for name, text in answers:
            f.write(f"== {name}\n{text[-400:]}\n\n".replace("\r", " "))

def wanted(name):
    return not ONLY or name in ONLY
results = []
answers = []

def add(name, status, note, ptok):
    # print each cell as it lands so a stall leaves the finished cells on disk
    print(f"{name}\t{status}\t{note}\t{ptok}", flush=True)

def post(payload, timeout=TIMEOUT):
    c = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    body = json.dumps(payload)
    c.request("POST", "/v1/chat/completions", body, {"Content-Type": "application/json"})
    r = c.getresponse()
    data = r.read()
    c.close()
    return r.status, data

def cell(name, payload, want_tool=False):
    if not wanted(name):
        return None
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
        # the full greedy text, reasoning first, so a thinking model is compared on all of it
        answers.append((name, (msg.get("reasoning_content") or "") + "\n--\n" + (msg.get("content") or "")))
        save()
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

def n_ctx():
    # the slot's context, which the app may have lowered to fit the cards (cardFitCtx)
    try:
        c = http.client.HTTPConnection(HOST, PORT, timeout=30)
        c.request("GET", "/props")
        js = json.loads(c.getresponse().read())
        c.close()
        return int(js["default_generation_settings"]["n_ctx"])
    except Exception:
        return 0

NCTX = n_ctx()
# a prompt past the cache window, then a small one: the cache must evict and still answer.
# band(t) is about 1.28 tokens per t; the prompt stays 1024 tokens under the context.
cell("evict", band(min(16000, (NCTX - 1024) * 100 // 130) if NCTX else 16000, TOPIC))
cell("after-evict", band(32, TOPIC))

# a prompt over the context: the engine must refuse it with 400 and keep serving
if wanted("over-ctx") and NCTX:
    try:
        st, data = post(band(NCTX * 100 // 120, TOPIC))
        if st == 400 and b"exceed_context_size_error" in data:
            add("over-ctx", "PASS", f"refused with 400 at n_ctx={NCTX}", 0)
        else:
            add("over-ctx", "FAIL", f"HTTP {st}: {data[:200]!r}", 0)
    except Exception as e:
        add("over-ctx", "FAIL", f"{type(e).__name__}: {e}", 0)
    cell("after-over-ctx", band(32, TOPIC))

# tools
cell("tools", {"model": MODEL,
               "messages": [{"role": "user", "content": "What is the weather in Lisbon? Use the tool."}],
               "tools": [{"type": "function", "function": {
                   "name": "get_weather", "description": "Get the current weather",
                   "parameters": {"type": "object", "properties": {"city": {"type": "string"}},
                                  "required": ["city"]}}}],
               # a thinking model plans the call first; 128 tokens ended Nemotron mid-plan
               "tool_choice": "auto", "max_tokens": 512, "temperature": 0.0}, want_tool=True)

# two concurrent requests
if not wanted("parallel2"):
    pass
elif PARALLEL >= 2:
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
    if not wanted("cancel-stream"):
        raise StopIteration
    c = http.client.HTTPConnection(HOST, PORT, timeout=30)
    c.request("POST", "/v1/chat/completions",
              json.dumps({"model": MODEL, "messages": [{"role": "user", "content": "Write a very long essay about the sea."}],
                          "max_tokens": 4096, "stream": True}),
              {"Content-Type": "application/json"})
    r = c.getresponse()
    r.read(64)
    c.close()
    add("cancel-stream", "PASS", "stream closed after 64 bytes", 0)
except StopIteration:
    pass
except Exception as e:
    add("cancel-stream", "FAIL", f"{type(e).__name__}: {e}", 0)
cell("after-cancel", band(64, TOPIC))

results = []  # each cell already printed; keep the list shape for the caller
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
    # the env the app builds for this launch (Server.swift): the last -ngl and --split-mode win
    local ngl="" split="" drafting=0 i
    for ((i = 0; i < ${#runargs[@]}; i++)); do
        case "${runargs[$i]}" in
            -ngl) ngl="${runargs[$((i+1))]}" ;;
            --split-mode) split="${runargs[$((i+1))]}" ;;
            -md) drafting=1 ;;
        esac
    done
    # A model above both cards' working sets never goes onto the cards whole: the driver pages GPU
    # memory through the GART until the kernel deadlocks (2026-11-04 01:15, the 28 GB 35B Q6_K at
    # -ngl 99 over both D700s; spinlock timeout in IOAccelSysMemory::unwire, the Mac rebooted). Only
    # -ngl 0 or an expert offload (--n-cpu-moe, -cmoe, -ot) may run it. The size is the link target's.
    if [ "$ngl" != 0 ] && ! offloads "${runargs[@]}"; then
        local msz; msz=$(stat -L -f %z "$model" 2>/dev/null || echo 0)
        if [ "$msz" -ge $((2 * ONECARD)) ]; then
            echo "refusing [$label]: $(basename "$model") is $msz bytes, above both cards' $((2 * ONECARD)), with every layer on the cards" >&2
            echo -e "$(basename "$model")\t$label\t(all)\tREFUSED\t$msz bytes on the cards would page GPU memory and panic the Mac\t0" >> "$TABLES/raw.tsv"
            return 1
        fi
    fi
    local runenv=() kv
    for kv in "${ENVS[@]}"; do
        case "${kv%%=*}" in
            # a model on the host leaves the cards out of the run
            GGML_METAL_DEVICE_LIST|GGML_METAL_DEVICE_INDEX|GGML_METAL_DEVICES) [ "$ngl" = 0 ] && continue ;;
            # set only on a tensor split; TOSH_MGPU_EVENTS deadlocks a layer split (ticket 10)
            TOSH_MGPU_PEER|TOSH_MGPU_EVENTS|TOSH_MGPU_TENSOR_GROUP|TOSH_MTL_QUEUE_DEPTH|TOSH_MIRROR_OUTPUT_HEAD)
                { [ "$ngl" = 0 ] || [ "$split" != tensor ]; } && continue ;;
        esac
        runenv+=("$kv")
    done
    # a DFlash draft on a tensor split keeps the target's head on every card
    if [ "$drafting" = 1 ] && [ "$ngl" != 0 ] && [ "$split" = tensor ]; then runenv+=(TOSH_MIRROR_OUTPUT_HEAD=1); fi
    echo "${runenv[*]}" > "$OUT/$(basename "$model" .gguf)-$label.env"
    echo "== $(basename "$model") [$label] port $port"
    # background env alone, not `cd && env`, so $! is the server (env execs it) and not a
    # subshell that kill_server would kill while the server kept running
    ( cd "$OUT" || exit 1; env "${runenv[@]}" "$SERVER" "${runargs[@]}" > "$log" 2>&1 & echo $! > "$OUT/current.pid" )
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

    python3 "$DRIVER" 127.0.0.1 "$port" "$model" "$OUT" "$PARALLEL" "$(basename "$model" .gguf)-$label" "${CELL_TIMEOUT:-900}" \
        "$(if [ "$label" = ngl0 ] || [ "$label" = ngl0nopo ]; then echo "${NGL0_CELLS:-}"; else echo "${CELLS:-}"; fi)" \
        > "$OUT/$(basename "$model" .gguf)-$label.cells.tsv" 2>&1

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
    if [ "$label" = draft ]; then
        local head
        head="$(grep -m1 -oE 'dflash lm head (copied to|kept on)[^(]*\([^)]*\)' "$log")"
        if [ -n "$head" ]; then
            echo -e "$(basename "$model")\t$label\tdrafter-head\tPASS\t$head\t0" >> "$TABLES/raw.tsv"
        elif ! grep -q 'offloaded 0/' "$log"; then
            # spec/0073 copies the head only when the target's head is on the host
            echo -e "$(basename "$model")\t$label\tdrafter-head\tSKIP\tthe target's head is on a card; no copy is made\t0" >> "$TABLES/raw.tsv"
        else
            echo -e "$(basename "$model")\t$label\tdrafter-head\tFAIL\tno 'dflash lm head' line in $log\t0" >> "$TABLES/raw.tsv"
        fi
    fi
    sleep 20
}

# --- greedy text of every mode against -ngl 0 ----------------------------------------------
compare_to_ngl0() {
    local stem="$1"
    python3 - "$OUT" "$stem" "$stem.gguf" "${PREV_OUT:-}" ${MODES:-tensor layer ngl0} >> "$TABLES/raw.tsv" <<'PY'
import json, os, sys
out, stem, name, prev, modes = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
def load(mode, where=None):
    p = f"{where or out}/{stem}-{mode}.answers.json"
    return json.load(open(p)) if os.path.exists(p) else None

def compare(row, ref, got, gated):
    bad, missing = [], []
    for cell in ("band16", "band300", "band1100"):
        a, b = ref.get(cell), got.get(cell)
        if a is None or b is None:
            missing.append(cell)
        elif a != b:
            i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
            bad.append(f"{cell} differs at offset {i}")
    if bad:
        print(f"{row}\t{'FAIL' if gated else 'DIFFERS'}\t{'; '.join(bad)}\t0")
    elif missing:
        print(f"{row}\tSKIP\tno answer for {', '.join(missing)}\t0")
    else:
        print(f"{row}\tPASS\tband16 band300 band1100 byte-identical\t0")

# every other mode against the app's launch (tensor), which a drafter must match: it is lossless;
# every GPU mode against the CPU (-ngl 0), reported only: the two backends sum in another order
for refmode in ("ngl0", "tensor"):
    ref = load(refmode)
    for mode in modes:
        if mode == refmode or (refmode == "tensor" and mode == "ngl0"):
            continue
        got = load(mode)
        if got is None:
            continue
        row = f"{name}\t{mode}\tidentical-vs-{refmode}"
        if ref is None:
            print(f"{row}\tSKIP\tno {refmode} run of this model\t0")
            continue
        compare(row, ref, got, gated=(refmode != "ngl0"))
# every mode against the same mode of the previous release
if prev:
    for mode in modes:
        got, ref = load(mode), load(mode, prev)
        if got is None:
            continue
        row = f"{name}\t{mode}\tidentical-vs-previous"
        if ref is None:
            print(f"{row}\tSKIP\tno {mode} run in {prev}\t0")
            continue
        compare(row, ref, got, gated=True)
PY
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
            # -ngl 0 with the prompt kept off the cards (core/0082 offloads it by default):
            # the pure CPU backend, for comparing with releases before 0082
            ngl0nopo) run_server "$model" "ngl0nopo" -ngl 0 --no-op-offload ;;
            draft)
                # the app's rule: the drafter is <stem>.dflash.gguf next to the model
                draft="${model%.gguf}.dflash.gguf"
                if [ -f "$draft" ]; then
                    run_server "$model" "draft" -md "$draft" --spec-type draft-dflash \
                        -ngld "${DRAFT_NGLD:-99}" -ctkd q8_0 -ctvd q8_0 -lv 4 ${DRAFT_EXTRA:-}
                else
                    echo -e "$(basename "$model")\tdraft\t(all)\tSKIP\tno $(basename "$draft") beside the model; the app loads no drafter\t0" >> "$TABLES/raw.tsv"
                fi ;;
            *)      echo "unknown mode: $mode" >&2 ;;
        esac
    done
    compare_to_ngl0 "$(basename "$model" .gguf)"
done

cat "$TABLES/raw.tsv" >> "$TABLES/stress.tsv"
echo "results: $TABLES/stress.tsv"
echo "logs:    $OUT"
