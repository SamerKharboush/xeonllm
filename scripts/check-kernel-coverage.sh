#!/bin/bash
# Contract 3.2: every pipeline name the host selector can compose for MUL_MAT and MUL_MAT_ID
# must exist in the shipped engine. Zero missing names.
#
# usage: scripts/check-kernel-coverage.sh <bin-dir>
#
# Two paths:
#   - engine built after this gate: TOSH_METAL_CHECK_KERNELS=1 makes the selector walk every
#     type x batch class x row count at library init and exit non-zero on a missing name.
#   - older engine (beta.5, for the record): no switch, so the names are compared against the
#     host_name() strings embedded in the binary, using the wide lists in the our selector.
set -u

BIN_DIR="${1:-}"
[ -n "$BIN_DIR" ] || { echo "usage: $0 <bin-dir>" >&2; exit 2; }
BIN_DIR="$(cd "$BIN_DIR" && pwd)"
SERVER="$BIN_DIR/llama-server"
OPS="$BIN_DIR/test-backend-ops"
[ -x "$SERVER" ] || { echo "no llama-server in $BIN_DIR" >&2; exit 2; }

echo "# bin: $BIN_DIR"
echo "# sha256 llama-server: $(shasum -a 256 "$SERVER" | cut -c1-16)"

if strings "$SERVER" | grep -q "TOSH_METAL_CHECK_KERNELS"; then
    echo "# path: engine self-check (TOSH_METAL_CHECK_KERNELS=1)"
    [ -x "$OPS" ] || { echo "no test-backend-ops in $BIN_DIR" >&2; exit 2; }
    fail=0
    for idx in 0 1; do
        log=$(GGML_METAL_DEVICE_INDEX=$idx TOSH_METAL_CHECK_KERNELS=1 \
              "$OPS" -b MTL0 -o RMS_NORM 2>&1)
        rc=$?
        miss=$(printf '%s\n' "$log" | grep -c "kernel missing:")
        echo "# card $idx: exit $rc, missing $miss"
        printf '%s\n' "$log" | grep "kernel missing:" | sed 's/^/MISSING /'
        [ "$rc" -eq 0 ] && [ "$miss" -eq 0 ] || fail=1
    done
    if [ "$fail" -eq 0 ]; then echo "PASS: 0 missing kernel names"; else echo "FAIL: missing kernel names"; fi
    exit "$fail"
fi

# --- legacy engine: no self-check switch --------------------------------------------------
# The wide lists below are the ones ggml_metal_library_get_pipeline_mul_mm / _mul_mm_id gate on.
DENSE_WIDE="bf16 bf16e f16 q8_0 q5_0 q5_1 q2_K q3_K q4_K q5_K pq2_0 ptq1_0 q6_K q4_0 q4_1 mxfp4 iq4_nl iq4_xs iq3_s iq2_s iq1_s iq1_m iq2_xxs iq2_xs iq3_xxs"
ID_WIDE="f16 q8_0 q5_0 q5_1 q2_K q3_K q4_K q5_K q6_K q4_0 q4_1 mxfp4 iq4_nl iq4_xs iq3_s iq2_s iq1_s iq1_m iq2_xxs iq2_xs iq3_xxs"

present="$(strings "$SERVER" | grep -o 'kernel_mul_mm[a-zA-Z0-9_]*' | sort -u)"

missing=0
check() {
    local name="$1" note="${2:-}"
    if ! printf '%s\n' "$present" | grep -qx "$name"; then
        echo "MISSING $name $note"
        missing=$((missing + 1))
    fi
}

# dense: a wide-capable type is asked for the plain kernel, the wide one, the 64-lane one and
# the pair; the pair only when the card is 64 lanes (both cards here are)
for t in $DENSE_WIDE; do
    check "kernel_mul_mm_${t}_f32"
    check "kernel_mul_mm_${t}_f32_w"
    check "kernel_mul_mm_${t}_f32_w64"
    check "kernel_mul_mm_${t}_f32_w_w64"
done
for t in $ID_WIDE; do
    check "kernel_mul_mm_id_${t}_f32"
    check "kernel_mul_mm_id_${t}_f32_w"
    check "kernel_mul_mm_id_${t}_f32_w64"
    check "kernel_mul_mm_id_${t}_f32_w_w64"
done

if [ "$missing" -eq 0 ]; then
    echo "PASS: 0 missing kernel names (static list, $(printf '%s\n' "$present" | grep -c 'kernel_mul_mm')) present"
else
    echo "FAIL: $missing missing kernel names"
fi
exit $(( missing > 0 ))
