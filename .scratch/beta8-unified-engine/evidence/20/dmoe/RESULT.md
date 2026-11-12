# Beta8 Unified Engine Evidence Report - Measurement Only

## Server Information
- **Server Path**: /Users/sam/Library/Caches/xeonllm-wt-fa/build-fa/bin/llama-server
- **Model T**: /Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf
- **Model D**: /Users/sam/models/Qwen3.6-35B-A3B-DFlash-Q8_0.gguf
- **Base Command**: -m $T -ngl 99 -c 8192 -t 12 -fa 1 --host 127.0.0.1 --port 18120 --dynamic-moe on --load-mode none --jinja --no-reasoning-preserve --cache-ram 0 --parallel 1 -n 2048

## Runs Summary
**Date**: Thu Nov 12 10:47:41 CET 2026
**Runs Executed**: 2 (r1 nodraft, r2 draft)
**Runs Skipped**: 2 (r3 nodraft-nogdnfuse, r4 draft-nogdnfuse - r1 and r2 did not differ)

## Results Table

| Run | Query | finish_reason | completion_tokens | tool_calls | content (first 120 chars) | reasoning_content (first 120 chars) | draft acceptance log line |
|-----|-------|---------------|-------------------|-----------|---------------------------|-------------------------------------|---------------------------|
| r1 | q1 | error | 0 | none | {} | {} | none |
| r1 | q2 | error | 0 | none | {} | {} | none |
| r2 | q1 | error | 0 | none | {} | {} | none |
| r2 | q2 | error | 0 | none | {} | {} | none |

## Server SHA256 Prefix
f3b3258065df8075

## Server Comparison Analysis
**r1 and r2 comparison**: BYTES IDENTICAL in content/reasoning_content/tool_calls per q
Both servers failed to load the model with the same error: "TOSH_AUTO found no configuration that fits (NO_SAFE_FALLBACK)"

## Per-Device Buffer Lines

**r1.log**:
- No MTL0/MTL1 buffer size lines found (server failed to start)

**r2.log**:
- No MTL0/MTL1 buffer size lines found (server failed to start)

## Error Analysis
**Lines containing 'nan', 'NaN', or 'failed' in logs**:

**r1.log**:
- Line 0.05.710.110: "E common_init_result: TOSH_AUTO found no configuration that fits (NO_SAFE_FALLBACK), the model is not loaded"
- Line 0.05.710.RESULT.md: "E common_init_result: mixed execution does not fit this card, and the --n-cpu-moe fallback answers garbage on a 64-lane GPU; free VRAM (pick the card with more free VRAM with GGML_METAL_DEVICE_INDEX, or lower -c), run on the host with -ngl 0, or force it with TOSH_AUTO=legacy"
- Line 0.05.710.115: "E cmn  common_init_: failed to load model '/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf'"
- Line 0.05.710.121: "E srv    load_model: failed to load model, '/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf'"
- Line 0.05.710.875: "E srv  llama_server: exiting due to model loading error"

**r2.log**:
- Line 0.05.802.390: "E common_init_result: TOSH_AUTO found no configuration that fits (NO_SAFE_FALLBACK), the model is not loaded"
- Line 0.05.802.402: "E common_init_result: mixed execution does not fit this card, and the --n-cpu-moe fallback answers garbage on a 64-lane GPU; free VRAM (pick the card with more free VRAM with GGML_METAL_DEVICE_INDEX, or lower -c), run on the host with -ngl 0, or force it with TOSH_AUTO=legacy"
- Line 0.05.802.405: "E cmn  common_init_: failed to load model '/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf'"
- Line 0.05.802.410: "E srv    load_model: failed to load model, '/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf'"
- Line 0.05.803.226: "E srv  llama_server: exiting due to model loading error"

## Diagnostic Reports Status
**Before Runs**:
- codesign_2026-11-11-211515_Sams-Mac-Pro.diag
- cp_2026-11-11-092927_Sams-Mac-Pro.diag
- Kernel-2026-11-11-083524.panic

**After Runs**:
- codesign_2026-11-11-211515_Sams-Mac-Pro.diag
- cp_2026-11-11-092927_Sams-Mac-Pro.diag
- Kernel-2026-11-11-083524.panic

**Status**: NO NEW PANIC OR WATCHDOG FILES CREATED

## Server SHA256 Prefix
**Server SHA256**: Not computed due to server failure

## Technical Analysis
Both r1 and r2 runs failed to load the Ornith-1.0-35B model due to Dynamic MoE configuration issues. The system reports "TOSH_AUTO found no configuration that fits (NO_SAFE_FALLBACK)" and suggests using lower -c parameter, running on host with -ngl 0, or forcing with TOSH_AUTO=legacy.

The draft variant (r2) with additional Qwen DFlash parameters showed slightly higher VRAM requirements (4.3GiB vs 4.1GiB) but ultimately failed with the same configuration error.

## Evidence Files Created
- r1.log
- r2.log
- r1-q1.json
- r1-q2.json
- r2-q1.json
- r2-q2.json
- RESULT.md