#!/bin/zsh
# check-exact-decoding.sh — ticket 13 exact-decoding gate.
# Usage: ENV='K=V ...' ARGS='--flag val ...' scripts/check-exact-decoding.sh \
#            <llama-server> <model.gguf> <drafter.gguf> <outdir>
# Uses one server at a time on port 18210; kill only the pid we start (in <outdir>/server.pid).
# Every arm writes its requests/responses/server log under <outdir>.
set -u
cd "$(dirname "$0")/.."

SRV=${1:?usage: $0 <llama-server> <model.gguf> <drafter.gguf> <outdir>}
MODEL=${2:?}
DRAFTER=${3:?}
OUT=${4:?}
PORT=18210
ARGS=${ARGS:-}
EXTRA_ENV=${ENV:-}
HELPER="$(dirname "$0")/check_exact_decoding_helper.py"
[ -x "$SRV" ] || { echo "no engine at $SRV" >&2; exit 2; }
[ -f "$MODEL" ] || { echo "missing model: $MODEL" >&2; exit 2; }
[ -f "$DRAFTER" ] || { echo "missing drafter: $DRAFTER" >&2; exit 2; }
mkdir -p "$OUT"

log() { print -r -- "$*" | tee -a "$OUT/script.log"; }

# --- server lifecycle ------------------------------------------------------------------
# perl alarm(1800) is mandatory on every launch.  $SRV_PID is the perl pid; exec makes
# it the server pid.  Only that pid is ever killed.
start_server() { # <logfile> <extra args ...>
    local l=$1; shift
    local vlog
    if grep -q 'restart' <<< "$l"; then vlog="-lv 4"; else vlog=""; fi
    perl -e 'alarm 1800; exec @ARGV' env ${=EXTRA_ENV} "$SRV" -m "$MODEL" --host 127.0.0.1 --port $PORT \
        --metrics ${=vlog} ${=ARGS} "$@" > "$l" 2>&1 &
    SRV_PID=$!
    echo $SRV_PID > "$OUT/server.pid"
    # health alone is not enough: /health answers before the model is loaded, and a
    # request sent then returns 400.  Wait for n_slots >= --parallel.
    local i
    local want=$(print -r -- "${=ARGS} $@" | grep -o -- '--parallel [0-9]*' | awk '{print $2}')
    [ -n "$want" ] || want=2
    local ready=0
    for i in $(seq 1 900); do
        curl -s -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"' || { sleep 1; continue; }
        # /health answers before the model is loaded; a request then 400s.  Gate on slots.
        n=$(curl -s -m 2 "http://127.0.0.1:$PORT/slots" 2>/dev/null \
            | python3 -c 'import json,sys
try: print(len(json.load(sys.stdin)))
except Exception: print(0)')
        [ "${n:-0}" -ge "$want" ] && { ready=1; break; }
        sleep 1
    done
    if [ "$ready" = 1 ]; then return 0; fi
    log "server not ready (health/slots) after 900 s; see $l"
    tail -n 8 "$l"
    return 1
}

stop_server() {
    [ -f "$OUT/server.pid" ] || return 0
    local pid=$(cat "$OUT/server.pid")
    if kill -0 $pid 2>/dev/null; then
        kill $pid 2>/dev/null
        local i
        for i in $(seq 1 60); do kill -0 $pid 2>/dev/null || break; sleep 1; done
        kill -9 $pid 2>/dev/null
    fi
    rm -f "$OUT/server.pid"
    sleep 2
}

trap 'stop_server' EXIT INT TERM

log "start $(date '+%Y-%m-%d %H:%M:%S %Z')"
log "binary: $SRV"
log "model: $MODEL"
log "drafter: $DRAFTER"
log "ENV: ${EXTRA_ENV:-none}"
log "ARGS: $ARGS"
MINE=$(lsof -nP -iTCP -sTCP:LISTEN | grep llama-server | grep -v ':8080 ' || true)
[ -z "$MINE" ] || { log "another llama-server of ours is listening: $MINE"; exit 2; }
MEM=$(memory_pressure | tail -1 | awk '{print $NF}')
log "memory before start: $MEM"

COMMON=(--parallel 2 --slot-save-path "$OUT/slots")
DRAFT=(-md "$DRAFTER" --spec-type draft-dflash --spec-draft-n-max 3)
mkdir -p "$OUT/slots"

# --- ARM OFF (reference) ---------------------------------------------------------------
log "=== ARM OFF (reference)"
start_server "$OUT/server-off.log" "${COMMON[@]}" || { log "OFF server failed to start"; exit 2; }
python3 "$HELPER" prompts "$OUT" off || exit 2
python3 "$HELPER" concurrent-solos "$OUT" off
OFF_OK=$?
stop_server

# --- ARM DRAFT -------------------------------------------------------------------------
log "=== ARM DRAFT"
start_server "$OUT/server-draft.log" "${COMMON[@]}" "${DRAFT[@]}" || { log "DRAFT server failed to start"; exit 2; }
python3 "$HELPER" prompts "$OUT" draft || { log "DRAFT prompts failed"; exit 2; }
python3 "$HELPER" draft-engagement "$OUT/server-draft.log" "$OUT/draft-engagement.json" | tee -a "$OUT/script.log"
python3 "$HELPER" concurrent-solos "$OUT" draft
python3 "$HELPER" concurrent-pair "$OUT" draft
python3 "$HELPER" conv-control "$OUT"          # 3 turns, one process, no restart
python3 "$HELPER" conv-first2 "$OUT"           # turn 1+2, then slot save

# STOP + restart with the same flags, then restore
stop_server
start_server "$OUT/server-draft-restart.log" "${COMMON[@]}" "${DRAFT[@]}" || { log "DRAFT restart failed"; exit 2; }
python3 "$HELPER" conv-restore "$OUT"          # POST restore, then turn 3 with cache_prompt true
python3 "$HELPER" restore-evidence "$OUT/server-draft-restart.log" "$OUT/restore-evidence.json" "$OUT" | tee -a "$OUT/script.log"
stop_server

# --- ARM OFF2 (determinism control: second OFF start) ----------------------------------
log "=== ARM OFF2 (determinism control)"
start_server "$OUT/server-off2.log" "${COMMON[@]}" || { log "OFF2 server failed to start"; exit 2; }
python3 "$HELPER" prompts "$OUT" off2 || { log "OFF2 prompts failed"; exit 2; }
stop_server

# --- comparisons and table --------------------------------------------------------------
python3 "$HELPER" report "$OUT" | tee "$OUT/table.tsv"
RESULT=${pipestatus[1]}   # the helper's status, not tee's: non-zero on any FAIL
log "end $(date '+%Y-%m-%d %H:%M:%S %Z')"
exit $RESULT
