#!/bin/zsh
# usage: cap.sh <OUT> <log> <capture-file> <ps-mode> <script args...>
# Runs scripts/stress-release.sh in the foreground of this shell, samples the server process
# command line (optionally its environment, filtered) once the server is up, then waits.
set -u
OUT="$1"; LOG="$2"; CAP="$3"; PSMODE="$4"; shift 4
rm -f "$CAP"
( "$@" > "$LOG" 2>&1; echo $? > "$OUT.rc" ) &
JOB=$!
for i in $(seq 1 300); do
    p=$(cat "$OUT/current.pid" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then break; fi
    sleep 1
done
sleep 2
if [ "$PSMODE" = cmd ]; then
    ps -o command= -p "$p" > "$CAP" 2>&1
else
    ps -E -o command= -p "$p" 2>/dev/null | tr ' ' '\n' | grep -E '^GGML_OP_OFFLOAD_MIN_BATCH=' > "$CAP"
fi
wait $JOB
echo "rc=$(cat "$OUT.rc")"