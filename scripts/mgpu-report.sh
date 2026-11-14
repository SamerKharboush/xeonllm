#!/bin/zsh
# Collects the multi-GPU numbers we cannot measure here (issue #51): device limits,
# layer vs tensor split, and the two opt-in sync paths. Send back the whole output.
#
#   ./scripts/mgpu-report.sh <model.gguf> [model-that-aborts.gguf]
#
# Uses the installed app by default; override with XEON_BIN=/path/to/bin.
set -uo pipefail

MODEL="${1:?usage: $0 <model.gguf> [model-that-aborts.gguf]}"
MODEL_ABORT="${2:-}"

BIN="${XEON_BIN:-/Applications/XeonLLM.app/Contents/Resources/bin}"
[ -x "$BIN/llama-bench" ] || BIN="$(dirname "$0")/../vendor/llama.cpp/build-static/bin"
[ -x "$BIN/llama-bench" ] || { echo "llama-bench not found; set XEON_BIN to the app's Resources/bin" >&2; exit 1; }

export GGML_METAL_CONCURRENCY_DISABLE=1
export XEON_FA_AMD=1
BENCH=("$BIN/llama-bench" -m "$MODEL" -ngl 99 --load-mode none -fa 1 -p 512 -n 128 -r 2)

echo "=== version"
"$BIN/llama-server" --version 2>&1 | head -2

echo "\n=== devices (maxBufferLength decides the ':1154 multi buffers' abort)"
swift -e 'import Metal; MTLCopyAllDevices().forEach { print($0.name, "maxBufferLength", $0.maxBufferLength, "bytes =", Double($0.maxBufferLength)/1073741824.0, "GiB") }' 2>/dev/null \
    || echo "swift not available, skipped"
echo "GGML_METAL_DEVICE_LIST=${GGML_METAL_DEVICE_LIST:-unset}"
echo "inherited sync flags (ignored, every run below sets its own):" \
     "XEON_MGPU_PEER=${XEON_MGPU_PEER:-unset}  XEON_MGPU_EVENTS=${XEON_MGPU_EVENTS:-unset}  XEON_MGPU_DEFER_WAITS=${XEON_MGPU_DEFER_WAITS:-unset}"

# Sync flags are set per run, so the numbers never depend on what the caller exported.
CLEAN=(env -u XEON_MGPU_PEER -u XEON_MGPU_EVENTS -u XEON_MGPU_DEFER_WAITS)

echo "\n=== layer vs tensor (no sync flags)"
"${CLEAN[@]}" "${BENCH[@]}" --split-mode layer  2>&1 | grep -vE "^ggml_metal|^load_"
"${CLEAN[@]}" "${BENCH[@]}" --split-mode tensor 2>&1 | grep -vE "^ggml_metal|^load_"

echo "\n=== tensor split: sync path matrix"
for cfg in "none:" "peer:XEON_MGPU_PEER=1" "events:XEON_MGPU_EVENTS=1" \
           "peer+events:XEON_MGPU_PEER=1 XEON_MGPU_EVENTS=1"; do
    echo "-- ${cfg%%:*}"
    "${CLEAN[@]}" ${=cfg#*:} "${BENCH[@]}" --split-mode tensor 2>&1 | grep -E "tg128|pp512"
done

echo "\n=== tensor split: deferred waits off/on"
"${CLEAN[@]}" XEON_MGPU_DEFER_WAITS=0 "${BENCH[@]}" --split-mode tensor 2>&1 | grep -E "tg128|pp512"
"${CLEAN[@]}" XEON_MGPU_DEFER_WAITS=1 "${BENCH[@]}" --split-mode tensor 2>&1 | grep -E "tg128|pp512"

echo "\n=== layer split: event hand-off off/on"
"${CLEAN[@]}" XEON_MGPU_EVENTS=0 "${BENCH[@]}" --split-mode layer 2>&1 | grep -E "tg128|pp512"
"${CLEAN[@]}" XEON_MGPU_EVENTS=1 "${BENCH[@]}" --split-mode layer 2>&1 | grep -E "tg128|pp512"

if [ -n "$MODEL_ABORT" ]; then
    echo "\n=== model that aborts (expected to fail, we want the exact line)"
    "$BIN/llama-bench" -m "$MODEL_ABORT" -ngl 99 --load-mode none -fa 1 -p 512 -n 32 -r 1 \
        --split-mode tensor 2>&1 | grep -iE "error|abort|not supported|buffers" | head -5
fi
