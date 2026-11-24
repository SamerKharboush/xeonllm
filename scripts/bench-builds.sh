#!/bin/bash
# Benchmark one extracted engine with the flags/env the XeonLLM app builds.
# usage: scripts/bench-builds.sh --engine DIR --model MODEL --mode bench|real \
#          --args-file FILE --env-file FILE --build TAG --args-set shipped|011 \
#          [--reps N] [--n-predict N] [--out TSV] [--note TEXT] [--plan-file FILE]
#
# The args file has one literal token per line; the env file has one KEY=VALUE per line.
# Nothing reads or writes the user's defaults, Application Support, or the server on 8080.
# Every GPU program is one process at a time under `perl -e 'alarm 1800; exec @ARGV'`.
set -u

ENGINE=""; MODEL=""; MODE=""; ARGS_FILE=""; ENV_FILE=""; BUILD=""; ARGS_SET=""
REPS=3; WARMS=0; NPRED=128; PORT=""; OUT=""; NOTE=""; PLAN_FILE=""; LABEL=""
SWNS="XEON_*"; TRANSLATION="native XEON_* names"
while [ $# -gt 0 ]; do
    case "$1" in
        --engine) ENGINE="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --args-file) ARGS_FILE="$2"; shift 2 ;;
        --env-file) ENV_FILE="$2"; shift 2 ;;
        --build) BUILD="$2"; shift 2 ;;
        --args-set) ARGS_SET="$2"; shift 2 ;;
        --reps) REPS="$2"; shift 2 ;;
        --n-predict) NPRED="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --note) NOTE="$2"; shift 2 ;;
        --plan-file) PLAN_FILE="$2"; shift 2 ;;
        --label) LABEL="$2"; shift 2 ;;
        --switch-namespace) SWNS="$2"; shift 2 ;;
        --translation) TRANSLATION="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
if [ -z "$ENGINE" ] || [ -z "$MODEL" ] || [ -z "$MODE" ] || [ -z "$ARGS_FILE" ] ||
   [ -z "$ENV_FILE" ] || [ -z "$BUILD" ] || [ -z "$ARGS_SET" ]; then
    echo "usage: $0 --engine DIR --model MODEL --mode bench|real --args-file FILE --env-file FILE --build TAG --args-set shipped|011 [options]" >&2
    exit 2
fi
case "$MODE" in bench|real) ;; *) echo "mode must be bench or real" >&2; exit 2 ;; esac

HERE="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$HERE/scripts/bench-builds-helper.py"
ENGINE="$(cd "$ENGINE" && pwd)"
BIN="$(basename "$ENGINE")"
BENCH="$ENGINE/llama-bench"; SERVER="$ENGINE/llama-server"
META="$ENGINE/../engine.meta.tsv"
[ -x "$BENCH" ] && [ -x "$SERVER" ] || { echo "no llama-bench/llama-server under $ENGINE" >&2; exit 2; }
[ -f "$META" ] || { echo "missing engine meta: $META" >&2; exit 2; }
[ -f "$MODEL" ] || { echo "missing model: $MODEL" >&2; exit 2; }

OUT="${OUT:-$HERE/.scratch/xeonllm-0-2/evidence/01/results.tsv}"
mkdir -p "$(dirname "$OUT")"
LOGDIR="$(dirname "$OUT")/logs"
mkdir -p "$LOGDIR"
LOGDIR="$(cd "$LOGDIR" && pwd)"
[ -f "$OUT" ] || printf 'timestamp\tbuild\tengine_sha16\targs_set\tmodel\tmode\trun\tstatus\tpp_ts\ttg_ts\tpp_len\ttg_len\tmethod\n' > "$OUT"

ARGS=()
while IFS= read -r _line || [ -n "$_line" ]; do [ -n "$_line" ] && ARGS+=("$_line"); done < "$ARGS_FILE"
ENVS=()
while IFS= read -r _line || [ -n "$_line" ]; do [ -n "$_line" ] && ENVS+=("$_line"); done < "$ENV_FILE"
read -r PP_TEST TG_TEST < <(python3 -I "$HELPER" labels --args "$ARGS_FILE")
if [ "$MODE" = bench ] && { [ -z "$PP_TEST" ] || [ -z "$TG_TEST" ]; }; then
    echo "bench args file has no -p/-n: $ARGS_FILE" >&2; exit 2
fi
if [ -z "$PP_TEST" ]; then PP_TEST=512; fi
TG_TEST="${TG_TEST:-$NPRED}"

LOCK="$LOGDIR/.gpu.lock"
while ! mkdir "$LOCK" 2>/dev/null; do sleep 5; done
PIDFILE="$LOGDIR/current-server.pid"
cleanup() {
    if [ -f "$PIDFILE" ]; then
        pid="$(cat "$PIDFILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    fi
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

SAFE_MODEL="$(basename "$MODEL" | sed 's/[^A-Za-z0-9._-]/_/g')"
SAFE_LABEL="$(printf '%s' "${LABEL:-${BUILD}-${ARGS_SET}-${MODE}}" | sed 's/[^A-Za-z0-9._-]/_/g')"

free_pct() { memory_pressure | tail -1 | sed -n 's/.*free percentage: \([0-9][0-9]*\)%.*/\1/p'; }
wait_ready() {
    if pgrep -f 'Downloads/Projects/Xenon' >/dev/null 2>&1; then
        echo "Xenon present: waiting until gone, then 5 min" >&2
        while pgrep -f 'Downloads/Projects/Xenon' >/dev/null 2>&1; do sleep 10; done
        sleep 300
    fi
    while :; do
        pct="$(free_pct)"
        if [ -n "$pct" ] && [ "$pct" -ge 50 ]; then return 0; fi
        sleep 10
    done
}
port8080() {
    if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then echo yes; else echo no; fi
}
sha16() { awk -v k="$1" -F '\t' '$1==k {print substr($2,1,16); exit}' "$META"; }
meta_val() { awk -v k="$1" -F '\t' '$1==k {print $2; exit}' "$META"; }

emit_row() {
    local run="$1" status="$2" pp="$3" tg="$4" pplen="$5" tglen="$6" reject="$7" logfile="$8" note="$9"
    local method
    method="$(python3 -I "$HELPER" method --meta "$META" --args "$ARGS_FILE" --env "$ENV_FILE" \
        --model "$MODEL" --mode "$MODE" --build "$BUILD" --args-set "$ARGS_SET" \
        --datetime "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
        --pp-length "${pplen:-}" --tg-length "${tglen:-}" \
        --n "$REPS" --warmups "$WARMS" --port8080 "$(port8080)" \
        --reject "$reject" --status "$status" --note "$NOTE ${note:-}" --log "$logfile" \
        --switch-namespace "$SWNS" --translation "$TRANSLATION")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$BUILD" "$(sha16 bench_sha256)" "$ARGS_SET" \
        "$MODEL" "$MODE" "$run" "$status" "$pp" "$tg" "${pplen:-}" "${tglen:-}" "$method" >> "$OUT"
}

# Model-size guard: a model above one card's working set never runs whole on one card.
MSZ="$(stat -L -f %z "$MODEL" 2>/dev/null || echo 0)"
ONECARD=0
for kv in ${ENVS[@]+"${ENVS[@]}"}; do
    case "$kv" in
        GGML_METAL_DEVICE_INDEX=*) ONECARD=1 ;;
        GGML_METAL_DEVICE_LIST=*) [[ "${kv#*=}" == *,* ]] || ONECARD=1 ;;
    esac
done
if [ "$ONECARD" = 1 ] && [ "$MSZ" -ge 5905580032 ]; then
    offload=0
    for i in "${!ARGS[@]}"; do
        case "${ARGS[$i]}" in
            --dynamic-moe) [ "${ARGS[$((i+1))]:-off}" != off ] && offload=1 ;;
            --n-cpu-moe|-ncmoe) [ "${ARGS[$((i+1))]:-0}" -gt 0 ] 2>/dev/null && offload=1 ;;
            -ot|--override-tensor) [[ "${ARGS[$((i+1))]:-}" == *=CPU* ]] && offload=1 ;;
        esac
    done
    if [ "$offload" = 0 ]; then
        emit_row 1 "NOT RUN: unsafe" "" "" "" "" "none" "" "model $MSZ bytes on one card without expert offload"
        exit 0
    fi
fi

if [ -n "$PLAN_FILE" ]; then
    check="$(python3 -I "$HELPER" plan --file "$PLAN_FILE")"
    case "$check" in
        unsafe*) emit_row 1 "NOT RUN: unsafe" "" "" "" "" "none" "" "$check"; exit 0 ;;
    esac
    NOTE="$NOTE; $check"
fi

if [ "$MODE" = bench ]; then
    PPLEN="$PP_TEST"; TGLEN="$TG_TEST"
    for ((i=1; i<=REPS; i++)); do
        wait_ready
        log="$LOGDIR/${SAFE_MODEL}-${SAFE_LABEL}-bench-r${i}.log"
        env ${ENVS[@]+"${ENVS[@]}"} perl -e 'alarm 1800; exec @ARGV' "$BENCH" ${ARGS[@]+"${ARGS[@]}"} > "$log" 2>&1 &
        pid=$!; echo "$pid" > "$PIDFILE"
        wait "$pid"; rc=$?
        : > "$PIDFILE"
        reject="$(python3 -I "$HELPER" scan --log "$log")"
        read -r pp tg < <(python3 -I "$HELPER" bench --log "$log" --pp-test "pp$PP_TEST" --tg-test "tg$TG_TEST")
        status=PASS
        [ -n "$pp" ] && [ -n "$tg" ] || status=FAIL
        [ "$rc" -eq 0 ] || status="FAIL(rc=$rc)"
        [ "$reject" != none ] && status="REJECTED"
        emit_row "$i/$REPS" "$status" "$pp" "$tg" "$PPLEN" "$TGLEN" "$reject" "$log" "bench rc=$rc"
    done
    exit 0
fi

# real mode: the app's llama-server launch, one discarded warm-up, then 3 reps, median.
WARMS=1
PORT="${PORT:-$(python3 -I "$HELPER" free-port)}"
case "$PORT" in 182[0-9][0-9]) ;; *) echo "port out of 18200-18299: $PORT" >&2; exit 2 ;; esac
RUNARGS=()
for ((i=0; i<${#ARGS[@]}; i++)); do
    a="${ARGS[$i]}"
    case "$a" in
        -m|--model|--host|--port) i=$((i+1)); continue ;;
        -m=*|--model=*|--host=*|--port=*) continue ;;
    esac
    RUNARGS+=("$a")
done
RUNARGS+=(-m "$MODEL" --host 127.0.0.1 --port "$PORT")
wait_ready
log="$LOGDIR/${SAFE_MODEL}-${SAFE_LABEL}-real-server.log"
reps="$LOGDIR/${SAFE_MODEL}-${SAFE_LABEL}-real-reps.tsv"
( cd "$LOGDIR" || exit 1; exec env ${ENVS[@]+"${ENVS[@]}"} perl -e 'alarm 1800; exec @ARGV' "$SERVER" "${RUNARGS[@]}" > "$log" 2>&1 ) &
pid=$!; echo "$pid" > "$PIDFILE"
up=0
for _ in $(seq 1 240); do
    kill -0 "$pid" 2>/dev/null || break
    if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then up=1; break; fi
    sleep 2
done
if [ "$up" != 1 ]; then
    reject="$(python3 -I "$HELPER" scan --log "$log")"
    emit_row "1/$REPS" "FAIL: server did not start" "" "" "server prompt" "$NPRED" "$reject" "$log" "port $PORT"
    exit 0
fi
perl -e 'alarm 1800; exec @ARGV' python3 -I "$HELPER" real --port "$PORT" --n-predict "$NPRED" \
    --warmups 1 --reps "$REPS" > "$reps" 2>&1
rc=$?
reject="$(python3 -I "$HELPER" scan --log "$log")"
kill "$pid" 2>/dev/null || true
for _ in $(seq 1 15); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
kill -9 "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
: > "$PIDFILE"

med_tg="$(awk -F '\t' '$1=="median" {print $3}' "$reps")"
med_pp="$(awk -F '\t' '$1=="median" {print $4}' "$reps")"
prompt_n="$(awk -F '\t' '$1=="rep" && NF>=6 {print $5; exit}' "$reps")"
status=PASS
[ -n "$med_tg" ] && [ -n "$med_pp" ] || status=FAIL
[ "$rc" -eq 0 ] || status="FAIL(rc=$rc)"
[ "$reject" != none ] && status="REJECTED"
# emit_row takes pp then tg. Before 2026-11-24 this line passed tg then pp, so every
# mode=real row written by tickets 01-02b has pp_ts and tg_ts swapped.
emit_row "1/$REPS" "$status" "$med_pp" "$med_tg" "${prompt_n:-server prompt}" "$NPRED" "$reject" "$log" \
    "reps=$reps port=$PORT rc=$rc"
