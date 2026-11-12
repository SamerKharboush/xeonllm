# 16: a dense model across both cards and RAM answers zeros — reproduced on today's engine, bisected to one fusion switch

Ticket: beta8 `issues/16-a-dense-model-across-both-cards-and-ram-answers-zeros.md` (tracks beta7 06 / ticket 68).

## Verdict

The bug **still reproduces on today's engine**. `-ngl 24 --split-mode layer` across both D700s answers
`Here000000000000…` instead of text.

**The single setting that removes the zeros is `TOSH_GDN_STATE_FUSION_DISABLE=1`** (the GDN
gated-delta-net recurrent-state fusion). With it set, `two24`, `two28` and the extra `twocard12`
placement all answer coherent text, byte-identical to each other, on every repeat.

The trigger is the **two-card split**, not host/GPU mixing: 12 layers on one card + host (`one12`) is
coherent; the same 12 layers spread over **both** cards (`twocard12`) answers zeros.

## Method line

```
llama-cli  sha256(f96866f469294a0c)  /Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-cli
engine    0.6.0-dev (build 11429, commit d81235049)   vendor HEAD d81235049384534c167caea52b85a694f6103d14 (2026-10-05)
series    local patch series applied on top of the d81235049 pin: 93 patches under patches/llama
          (core/…0082, metal/…0083, mgpu/…0018, model/…0079, moe/…0071, quant/…0014, spec/…0073,
          server/…0077, ui/…0059); vendor tree = 154 modified + 32 untracked paths vs the pin
model     Qwen3.6-27B-NEO-CODE-HERE-2T-OT-Q6_K.gguf  (arch qwen35, dense, 64 layers, n_embd 5120,
          n_head 24 / n_head_kv 4, ssm state_size 128, full_attention_interval 4, Q6_K, 20.85 GiB)
flags     -m <model> -c 4096 -ub 128 -b 512 -t 12 -fa on -st --temp 0 -s 1 -n 64
          -p "Explain what a binary search tree is." -v        (seed 1, temp 0.0, n_predict 64)
device    both cards: GGML_METAL_DEVICE_LIST=0,1   (honoured — ggml-metal-device.m:1793-1795,
          ggml-metal.cpp:1689; each log shows "ggml_metal: device 0:" and "device 1:" and
          "using device MTL0 … (dev p0/v0)" + "MTL1 … (dev p0/v1)")
          one card + host: GGML_METAL_DEVICE_INDEX=1  (pins physical GPU 1)
guard     every GPU program wrapped in  perl -e 'alarm 900; exec @ARGV' , one at a time, foreground
```

### Per-card buffer lines (from the logs, model + KV + compute + recurrent state)

| cell | MTL0 model / KV / compute / RS (MiB) | MTL1 model / KV / compute / RS (MiB) | self total MTL0 | self total MTL1 | fit "projected to use" |
|---|---|---|---|---|---|
| host (`-ngl 0`) | — (all on CPU; `CPU_Mapped model buffer size = 21348.16`) | — | CPU KV 256.00, RS 149.62, CPU compute 28.74 | — | 149 MiB device |
| two24 | 3574.73 / 48.00 / 149.95 / 28.05 | 4562.92 / 48.00 / 60.21 / 24.94 | 3800.73 | 4696.07 | 8496 MiB |
| two28 | 4174.95 / 48.00 / 149.95 / 34.29 | 5154.28 / 64.00 / 60.21 / 28.05 | 4407.19 | 5306.54 | 9713 MiB |
| one12 (extra) | 4562.92 / 48.00 / 149.95 / 24.94 | — | 4785.81 | — | 4785 MiB |
| twocard12 (extra) | 1791.79 / 16.00 / 149.95 / 15.59 | 2771.13 / 32.00 / 60.21 / 9.35 | 1973.33 | 2872.69 | 4846 MiB |

No card exceeds the 5600 MiB ceiling in any cell (max self total 5306.54 MiB on MTL1 of two28).

Layer placement per cell (`load_tensors: layer N assigned to device …`, `offloaded N/65 layers to GPU`):

| cell | CPU | MTL0 | MTL1 | offloaded |
|---|---|---|---|---|
| two24 | 0–40 (41) | 41–52 (12) | 53–64 (12) | 24/65 |
| two28 | 0–36 (37) | 37–50 (14) | 51–64 (14) | 28/65 |
| one12 | 0–52 (53) | 53–64 (12) | — | 12/65 |
| twocard12 | 0–52 (53) | 53–58 (6) | 59–64 (6) | 12/65 |

## Run table

`cmp vs host` = first differing byte of `<cell>.gen` against `host.gen`.
"coherent" = text that answers the question; "zeros" = `Here0000…`.
First 120 chars are the literal first 120 bytes of `<cell>.gen` with newlines collapsed to spaces; the
zeros runs are only 88 bytes long, so their whole output is shown.

| # | cell | setting (env + flags beyond the common set) | devices used | result | first 120 chars | cmp vs host |
|---|---|---|---|---|---|---|
| 1 | host | `GGML_METAL_DEVICE_INDEX=1` `-ngl 0` | MTL0 only (0 layers) | coherent (reference, 266 B) | `[Start thinking] Here's a thinking process: 1. **Understand User Request:** The user wants an explanation of what a` | — (is host) |
| 2 | two24 | `GGML_METAL_DEVICE_LIST=0,1` `-ngl 24 --split-mode layer` | MTL0+MTL1 | **zeros** (88 B) | `[Start thinking] Here000000000000000000000000000000000000000000000000000000000000000` | differ char 24, line 4 |
| 3 | two24-r2 | same as #2 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 4 | two24-r3 | same as #2 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 5 | two24-r4 | same as #2 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 6 | two24-fusdbg | #2 + `GGML_METAL_FUSION_DEBUG=1` | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 7 | two24-nofuse | #2 + `GGML_METAL_FUSION_DISABLE=1` + all 9 op-level `TOSH_*_DISABLE` | MTL0+MTL1 | coherent (270 B) | `[Start thinking] Here's a thinking process: 1. **Understand User Request:** The user wants an explanation of what a` | differ char 178, line 8 |
| 8 | two24-fusdisable | #2 + `GGML_METAL_FUSION_DISABLE=1` only | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 9 | two24-opfus | #2 + all 9 op-level `TOSH_*_DISABLE`, global fusion ON | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 10 | two24-qkv | #2 + `TOSH_QKV_FUSION_DISABLE=1` | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 11 | two24-mgpu | #2 + `TOSH_MGPU_FUSE_ADD_DISABLE=1 TOSH_MGPU_FUSED_EXCHANGE_DISABLE=1` | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 12 | two24-sw3 | #2 + `TOSH_SWIGLU_FUSION_DISABLE=1 TOSH_GATE_ADD_FUSION_DISABLE=1 TOSH_GDN_STATE_FUSION_DISABLE=1` | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 13 | two24-gdn | #2 + `TOSH_GDN_STATE_FUSION_DISABLE=1` only | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 14 | two24-gdn-r2 | same as #13 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 15 | two24-gdn-r3 | same as #13 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 16 | two24-gdn-r4 | same as #13 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 17 | two24-gdn-r5 | same as #13 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 18 | two24-noGdn **(control)** | #2 + all 9 op-level `TOSH_*_DISABLE` **except** `TOSH_GDN_STATE_FUSION_DISABLE` | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 19 | two28 | `GGML_METAL_DEVICE_LIST=0,1` `-ngl 28 --split-mode layer` | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 20 | two28-r2 | same as #19 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 21 | two28-r3 | same as #19 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 22 | two28-r4 | same as #19 | MTL0+MTL1 | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 23 | two28-gdn | #19 + `TOSH_GDN_STATE_FUSION_DISABLE=1` | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 24 | two28-gdn-r2 | same as #23 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 25 | two28-gdn-r3 | same as #23 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 26 | two28-gdn-r4 | same as #23 | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 27 | one12 *(extra)* | `GGML_METAL_DEVICE_INDEX=1` `-ngl 12 --split-mode layer` | MTL0 only (12 layers) + host | coherent (270 B) | same as #7 | differ char 178, line 8 |
| 28 | twocard12 *(extra)* | `GGML_METAL_DEVICE_LIST=0,1` `-ngl 12 --split-mode layer` | MTL0+MTL1 (12 layers split 6/6) | **zeros** (88 B) | same as #2 | differ char 24, line 4 |
| 29 | twocard12-gdn *(extra)* | #28 + `TOSH_GDN_STATE_FUSION_DISABLE=1` | MTL0+MTL1 | coherent (270 B) | same as #7 | differ char 178, line 8 |

N per cell: two24 plain **4** (#2–#5), two24+fix **5** (#13–#17), two28 plain **4** (#19–#22),
two28+fix **4** (#23–#26), host 1, extra placements 1 each.

Byte-identity groups (all coherent GPU runs are byte-identical to each other, 270 B):
`two24-gdn, two24-gdn-r2..r5, two24-fusdisable, two24-nofuse, two24-opfus, two24-sw3, two28-gdn,
two28-gdn-r2..r4, one12, twocard12-gdn`.
All zeros runs are byte-identical to each other (88 B): `two24, two24-r2..r4, two24-fusdbg,
two24-mgpu, two24-noGdn, two24-qkv, two28, two28-r2..r4, twocard12`.

Host differs from every coherent GPU run at **char 178, line 8**: host says
`2.  **Identify Key Concepts to Cover:**` where the GPU runs say `2.  **Identify Key Concepts:**`.
That difference is **not** the bug: `one12` (12 layers on one card, fusion untouched) differs from host at
exactly the same byte, so any offload changes the greedy path at temp 0. All 12 coherent GPU runs agree
byte-for-byte with each other.

## How the single switch was isolated

1. `GGML_METAL_FUSION_DEBUG=1` on two24 still gives zeros → the zeros are not a fusion-count artefact.
   Debug stats on that run: `RMS_NORM+MUL: 2479`, `RMS_NORM+SCALE: 1072`, `SSM_CONV+UNARY: 536`
   (and 2613 / 1206 / 603 on the second pass).
2. Global `GGML_METAL_FUSION_DISABLE=1` alone fixes it (log: `ggml_metal_init: use fusion = false`),
   so the cause is inside the fusion set.
3. Global ON + all nine op-level disables also fixes it (`use fusion = true`, no op-level fusion left).
4. Switching the op-level disables back on one at a time: QKV off → still zeros; MGPU fuse-add and
   fused-exchange off → still zeros; SWIGLU+GATE_ADD+GDN_STATE off → coherent.
5. **Control (run #18)**: all nine op-level disables **except** `TOSH_GDN_STATE_FUSION_DISABLE` →
   **zeros again**. Removing only GDN_STATE from the working set restores the failure, so GDN_STATE is
   the single switch.
6. `TOSH_GDN_STATE_FUSION_DISABLE=1` alone on two24 → coherent, and it also fixes two28 (#23) and the
   extra two-card placement twocard12 (#29).

Kernel-variant evidence in the logs corroborates it. Failing runs compile the *row-gathered, folded*
GDN variant:

```
two24      : kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=0_l2=00
              kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=1_fold=1_raw=1_l2=11
two24-gdn  : kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=0_l2=00
              kernel_gated_delta_net_f32_lpr16_ne20=128_ne30=1_K=1_rows=0_fold=0_raw=1_l2=00
```

i.e. with the switch off the engine never compiles the fused `rows=1_fold=1` state kernel.

## Root cause

`ggml_metal_gdn_state_fusion_on()` (`ggml/src/ggml-metal/ggml-metal-ops.cpp:2359`) lets a single-sequence
`gated_delta_net` read its recurrent state straight out of the recurrent cache row and write the new state
back, so the GET_ROWS gather before it and the CPY copy after it are skipped
(`ggml_metal_gdn_rows_src` :2314, `ggml_metal_gdn_fold_dst` :2336, `ggml_metal_gdn_state_skip` :2372).
The switch is:

```c
static const bool disabled = TOSH_ENV("TOSH_GDN_STATE_FUSION_DISABLE") != nullptr;
return ctx->use_fusion() && !ctx->use_concurrency && !disabled;
```

Its own comment records the same failure on the 35B MoE across both D700s ("the fused state gather/copy
answers with NaN … root cause open"); here the same path answers **zeros** on a dense model.

The recurrent state is allocated per layer on the layer's own device
(`src/llama-memory-recurrent.cpp:85-124`, `model.dev_layer(i)`), so with a layer split across two cards
the state gather and the state write-back for one layer can sit on a different card than the one that runs
the layer's op. The fusion predicate in `ggml_metal_gdn_state_fusion_on()` does not look at devices at
all — it only asks whether fusion is on, whether concurrency is on, and whether the env switch is set —
so the fused kernel can be asked to read the state row and write the new state across a card boundary.
The buffer ids the fused kernel binds come from the tensors themselves
(`ggml_metal_ops.cpp:2488` state, `:2491` new state), and the two cards have separate Metal buffers.

What is **established by measurement** here: the fused GDN state path is the cause (the switch isolates
it), and the two-card split is the trigger (one12 coherent vs twocard12 zeros, same 12 layers, same
model, same flags). What is **not** established by measurement — no instrumentation could be added, as
the brief forbids building and editing — is the exact byte-level mechanism inside the fused kernel; the
device-blindness of the predicate is the strongest candidate, and the source comment on the same switch
records the identical failure mode (a wrong answer from the fused state gather/copy) on the 35B MoE
across both D700s with "root cause open".

Diagnostic grep on a zeros run (`two24.err`) and on the fixed run, as the brief asks:

* `nan` → **0 hits** in both. No NaN reaches the sampler.
* `inf` → 5 hits in both, all of them logit-bias setup
  (`added <|endoftext|> logit bias = -inf`, `added <|im_end|> …`, `added <|fim_pad|> …`,
  `added <|repo_name|> …`, `added <|file_sep|> …`). No `-inf` in the generated text.
* `failed` → 0 hits in both.
* `copy` → 26 hits in both, all of them the recurrent-state view node
  (`input tensor 'rs_s_copy' … is used by node 'rs_s_copy (view)' (VIEW)`). No copy error is reported.
* `split` → identical in both: `graph (pp bs=128, tg bs=1): nodes = 3802 / 3610, splits = 627 / 3,
  input objects = 4 / 4, input tensors = 10 / 10`. Same graph size in the failing and the fixed run, so
  the failure is in the values, not in the graph shape.

## What is *not* fixed

`TOSH_GDN_STATE_FUSION_DISABLE=1` is a workaround, not a fix: it disables the GDN state fusion for every
model, on every card layout, including the layouts that are correct today. The underlying defect is in the
fused cross-device recurrent-state gather/copy; the correct fix is to make that path device-aware (or to
disable it automatically when the state and the op live on different devices, the way the Dynamic-MoE
branch already does for the 35B).

## Not run, and why

* **beta7 06's "text identical to the host reference for 400 tokens"** — not tested: the brief caps the
  generation at `-n 64` and forbids long prompts, so 400-token equality with the host was out of reach.
  At 64 tokens the coherent GPU runs differ from the host run at char 178 (see above), so that gate is
  **not** met literally by any GPU placement, including the one-card `one12` that never hits the bug.
* **Step 4b of the brief** (`-fa off`, then `TOSH_MTL_CB_TARGET_MS=0`, then `--no-op-offload`) — not run:
  step 4a isolated the setting (a fusion switch), so 4b was not reached. The brief's 4b ends with the
  one-card placement, which was run as the extra `one12` cell.
* **`one12` and `twocard12`** are extra placements outside the brief's allowed list
  (host / two24 / two28). They were added because they are the discriminating pair for the trigger; they
  are marked *(extra)* in the table above.
* **Nothing was built, no source/patch/script/spec was edited, and no git write command
  (commit/tag/push/stash/reset/checkout/clean) was run.** All artefacts are the `.out` / `.err` / `.gen`
  files in this directory plus `monitor.log`.

## Safety log

`ls -t /Library/Logs/DiagnosticReports/ | head -3` was run before the first GPU program and after every
one of the 29 runs. The listing never changed:

```
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
cp_2026-11-11-092927_Sams-Mac-Pro.diag
Kernel-2026-11-11-083524.panic
```

43 entries in the directory, unchanged from before the first run. The `Kernel-2026-11-11-083524.panic`
is pre-existing (dated the day before this work) and was already present in the "before" listing — **no new
panic, watchdog or gpuRestart report was produced.** Every run exited 0 in 40–45 s.
