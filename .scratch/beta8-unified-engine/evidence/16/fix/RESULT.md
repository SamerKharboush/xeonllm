# Ticket 16 - fix: disable GDN state fusion when more than one Metal device is in use

Date: 2026-11-12 (started 08:28 CET, finished 09:0x CET)
Repo: `/Users/sam/Library/Caches/xeonllm-wt-fa` (detached at `eaf77ffe8`, "metal/0083")
Status: **changes UNCOMMITTED in the worktree** (nothing committed, pushed, stashed, reset, checked out or cleaned).

## Build

```
cmake --build build-fa -j8 --target llama-cli
```

Only warning: pre-existing `-Wmissing-field-initializers` at `ggml/src/ggml-metal/ggml-metal-ops.cpp:6242`.

Binary sha256:

```
eaa67e8cbf12daeed533f072c1f791ce36c0b9beb50edac40b73683c04f63665  build-fa/bin/llama-cli
```

sha256 prefix: **`eaa67e8cbf12daee`**

Build banner reported by the CLI: `build : b11432-eaf77ffe8`.

## Change (3 files, 16 insertions, 0 deletions)

Full diff: `fix.diff` (same content as below).

```diff
--- a/ggml/src/ggml-metal/ggml-metal-device.h
+++ b/ggml/src/ggml-metal/ggml-metal-device.h
@@ -379,6 +379,9 @@ void * ggml_metal_device_get_obj  (ggml_metal_device_t dev); // id<MTLDevice>
 int   ggml_metal_device_index(ggml_metal_device_t dev);       // the card's index in the backend's device order
 void * ggml_metal_device_get_queue(ggml_metal_device_t dev); // id<MTLCommandQueue>
 
+// number of Metal devices the backend registered (GGML_METAL_DEVICES / GGML_METAL_DEVICE_LIST)
+int ggml_metal_device_count(void);
+
 // per-context queue: the first context gets the shared device queue, later
 // ones an owned queue so their uploads can overlap compute
 void * ggml_metal_device_acquire_queue(ggml_metal_device_t dev, bool * owned); // id<MTLCommandQueue>
--- a/ggml/src/ggml-metal/ggml-metal-ops.cpp
+++ b/ggml/src/ggml-metal/ggml-metal-ops.cpp
@@ -2358,6 +2358,14 @@ static const ggml_tensor * ggml_metal_gdn_fold_dst(ggml_metal_op_t ctx, int idx)
 
 static bool ggml_metal_gdn_state_fusion_on(ggml_metal_op_t ctx) {
     static const bool disabled = TOSH_ENV("TOSH_GDN_STATE_FUSION_DISABLE") != nullptr;
+    // the fused state gather/copy is wrong when more than one Metal device is in use: the dense
+    // qwen35 27B layer split over two D700s answered zeros (beta 8 ticket 16), root cause still
+    // open; the unfused path is correct there
+    static const bool multi = TOSH_ENV("TOSH_GDN_STATE_FUSION_MULTI") != nullptr &&
+                              atoi(TOSH_ENV("TOSH_GDN_STATE_FUSION_MULTI")) != 0;
+    if (!multi && ggml_metal_device_count() > 1) {
+        return false;
+    }
     // with expert layers on two cards the fused state gather/copy answers with NaN (found on the
     // 35B with Dynamic MoE across both D700s, root cause open); the unfused path is correct there
 #ifdef TOSH_ENABLE_DYNAMIC_MOE
--- a/ggml/src/ggml-metal/ggml-metal.cpp
+++ b/ggml/src/ggml-metal/ggml-metal.cpp
@@ -28,6 +28,11 @@
 // note: can be overridden with GGML_METAL_DEVICES env to simulate virtual devices
 static int g_devices = 1;
 
+// number of Metal devices the backend registered (GGML_METAL_DEVICES / GGML_METAL_DEVICE_LIST)
+int ggml_metal_device_count(void) {
+    return g_devices;
+}
+
 // forward declaration
 static bool ggml_backend_buffer_is_metal(ggml_backend_buffer_t buffer);
```

What it does:

- `ggml_metal_device_count()` exposes the backend's registered Metal device count (`g_devices`, set from `GGML_METAL_DEVICES` / `GGML_METAL_DEVICE_LIST` in `ggml_backend_metal_reg()`). No pre-existing accessor for this existed.
- `ggml_metal_gdn_state_fusion_on()` now returns `false` when more than one Metal device is registered, so GDN state fusion is off for every multi-card placement.
- The pre-existing Dynamic MoE guard (`TOSH_ENABLE_DYNAMIC_MOE` branch) and `TOSH_GDN_STATE_FUSION_DISABLE` are both kept and unchanged; the new multi-device guard is checked first.
- `TOSH_GDN_STATE_FUSION_MULTI=1` (non-zero value) re-enables the fused path even with >1 device. This is the escape hatch / A-B switch used by gate 2.

## Runs

Model (only model used):

```
/Users/sam/models/Qwen3.6-27B-Heretic-Uncensored-FINETUNE-NEO-CODE-Di-IMatrix-MAX-GGUF/Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf
```

Common flags for every run:

```
-c 4096 -ub 128 -b 512 -t 12 -fa on -st --temp 0 -s 1 -n 64 -p "Explain what a binary search tree is." -v
```

Each run was wrapped in `perl -e 'alarm 900; exec @ARGV'`. One GPU program at a time; no GPU program ran during the build.

| run | placement | env | result | gen bytes | first 120 chars of gen | cmp vs one12.gen |
|---|---|---|---|---|---|---|
| one12 | 1 card, 12 layers | `GGML_METAL_DEVICE_INDEX=1 -ngl 12 --split-mode layer` | coherent | 269 | `[Start thinking]\n\nHere's a thinking process:\n\n1.  **Understand User Request:** The user wants an explanation of what a b` | (baseline) |
| twocard12 | 2 cards, 12 layers | `GGML_METAL_DEVICE_LIST=0,1 -ngl 12 --split-mode layer` | coherent (fix works) | 269 | `[Start thinking]\n\nHere's a thinking process:\n\n1.  **Understand User Request:** The user wants an explanation of what a b` | IDENTICAL |
| two24 | 2 cards, 24 layers | `GGML_METAL_DEVICE_LIST=0,1 -ngl 24 --split-mode layer` | coherent (fix works) | 269 | `[Start thinking]\n\nHere's a thinking process:\n\n1.  **Understand User Request:** The user wants an explanation of what a b` | IDENTICAL |
| twocard12-multi | 2 cards, 12 layers | `GGML_METAL_DEVICE_LIST=0,1 TOSH_GDN_STATE_FUSION_MULTI=1 -ngl 12 --split-mode layer` | **zeros** (fused path forced back on) | 87 | `[Start thinking]\n\nHere000000000000000000000000000000000000000000000000000000000000000\n\n` | DIFFERENT |

`cmp one12.gen twocard12.gen` -> identical (exit 0).
`cmp one12.gen two24.gen` -> identical (exit 0).
`cmp one12.gen twocard12-multi.gen` -> differ (exit 1).

Note on the zeros signature: the fused-path failure emits literal ASCII `'0'` characters (not NUL bytes), starting right after `Here`, 87 bytes total.

Gate 2 confirms the escape hatch works: with `TOSH_GDN_STATE_FUSION_MULTI=1` the old broken behavior (zeros) comes back on the same two-card placement.

## Gate 3: kernel-variant evidence

Kernel names come from the `-v` stderr logs (`kernel_gated_delta_net_..._rows=%d_fold=%d_raw=%d_l2=%d%d`).

one12 (single card, fusion stays ON) - only the fused variant appears:

```
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=0_l2=00
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=1_l2=11
```

twocard12 (two cards, guard OFF) - only the unfused variant appears, no `rows=1_fold=1` line:

```
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=0_l2=00
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=1_l2=00
```

two24 (two cards, guard OFF) - same as twocard12:

```
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=0_l2=00
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=1_l2=00
```

twocard12-multi (`TOSH_GDN_STATE_FUSION_MULTI=1`, fusion forced ON) - fused variant is back:

```
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=0_l2=00
kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=1_l2=11
```

## Gate 4: no Advanced SIMD in the shipped binary

```
$ otool -tv build-fa/bin/llama-cli | grep -cE 'vfmadd|vfmsub|vfnmadd|vpbroadcast|vinserti128|vextracti128|vpgather'
0
```

(`grep` exit code 1 because there was no match, as expected.)

## DiagnosticReports (safety check)

Before the first GPU program (baseline) and after the last one: identical, 43 entries in `/Library/Logs/DiagnosticReports/`.

Before and after, newest 3 names were the same:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

`Kernel-2026-11-11-083524.panic` is pre-existing (dated 2026-11-11, before this work started). Newest panic/watchdog/gpuRestart entries in the directory are all pre-existing:

```
Kernel-2026-11-11-083524.panic
WindowServer_2026-11-10-213045_Sams-Mac-Pro.userspace_watchdog_timeout.spin
WindowServer_2026-11-10-213011_Sams-Mac-Pro.userspace_watchdog_timeout.spin
Kernel-2026-11-07-144047.panic
WindowServer_2026-11-07-143623_Sams-Mac-Pro.userspace_watchdog_timeout.spin
```

**No new `*.panic`, `*watchdog*` or `*.gpuRestart` was produced by any of the four runs.** Per-run snapshots are in `*.diag-before` / `*.diag-after`.

## Root cause (read-only investigation, not implemented)

Open. What the code reading established:

- `llama_memory_recurrent` allocates each layer's recurrent state (RS) cache on that layer's device buffer (`model.dev_layer(i)` buft). In the twocard12 split the layers land on different cards (e.g. MTL0_Private and MTL1_Private) and the GDN layer plus its KV go to different devices.
- The fused GDN state path (`ggml_metal_op_gated_delta_net` with `rows=1`/`fold=1`) reads and writes the recurrent cache buffer directly via the state base offsets in `kernels/gated_delta_net.metal` instead of going through GET_ROWS/CPY. When the op and the cache buffer live on different cards, the fused gather/write-back can end up on a card other than the one that owns the data, which matches the observed all-zeros state output.
- The unfused path (`rows=0_fold=0`, separate GET_ROWS + CPY) uses ordinary buffer ops that honour device ownership, and it produces correct output on both cards (byte-identical to the single-card run).

This is a hypothesis consistent with the evidence, not a proven mechanism; no fix beyond the guard was implemented, as instructed.

## Artifacts

```
evidence/16/fix/
  RESULT.md                  this report
  fix.diff                   the uncommitted diff (3 files)
  run.sh                     run helper
  monitor.log                idle-process monitor timeline
  one12.{cmd,out,err,gen,diag-before,diag-after}
  twocard12.{cmd,out,err,gen,diag-before,diag-after}
  two24.{cmd,out,err,gen,diag-before,diag-after}
  twocard12-multi.{cmd,out,err,gen,diag-before,diag-after}
```

## Not run

- No root-cause fix was implemented (guard only, per ticket scope).
- No other placements (e.g. `-ngl 28`, `GGML_METAL_DEVICES=2` virtual devices, three-card) were tested in this round.
- No benchmark run; only correctness generation was exercised.
- Nothing committed, pushed, or stashed; the worktree holds exactly the 3 modified files listed above.
