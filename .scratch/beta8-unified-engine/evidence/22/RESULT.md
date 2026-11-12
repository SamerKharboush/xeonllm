# Ticket 22 - beta 8 llama-bench aborts at pp2048 with GGML_ASSERT(id >= 0 && id < n_expert)

Date: 2026-11-12, ~19:50-21:22 CET. Worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`
(XeonLLM fork, HEAD `f9b6c9dcd` "metal/0085"), card 1 (`GGML_METAL_DEVICE_INDEX=1`),
model `/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf`, always `-ngl 0`.

## Summary

- The abort **did not reproduce** on this worktree build, on this card, at any pp size up to 4096.
- The abort **is real and already captured** in the shipped-binary gate evidence
  (`evidence/gates-beta8/out/pp-35b-host.{csv,err}`): build `d81235049`/11429, same host,
  card 0, aborted at `ggml/src/ggml-backend.cpp:2193` after 6 passing rows.
- Applied the ticket's sanctioned fallback: host-weight `MUL_MAT_ID` no longer takes op
  offload unless `TOSH_OFFLOAD_MOE` is set. Dense `MUL_MAT` offload untouched.
- With the fallback in place, forcing `TOSH_OFFLOAD_MOE=1` on this card re-enables the
  offloaded path and still does not abort. So the offloaded path is reachable here and the
  fallback is safe, but the abort trigger is card/build specific and was **not** isolated to
  a root cause line.

## Evidence files

| File | What it shows |
|---|---|
| `repro/a1.csv`, `repro/a2.csv` | unmodified tree, `-fa 1 -p 2048 -n 0 -r 1`, rc=0 |
| `repro/b1.csv` | unmodified, same + `--no-op-offload 1`, rc=0 |
| `repro/c1.csv` | unmodified, `-p 2048 -b 512 -ub 512`, rc=0 |
| `repro/d1.csv` | unmodified, `-p 2048 -ub 256`, rc=0 |
| `repro/e1.csv` | unmodified, `-p 4096 -n 0 -r 1`, rc=0 |
| `repro/rc.txt` | `a1..e1 rc=0` |
| `repro/dbg-sched.csv/.err` | instrumented unmodified run, `-p 16` |
| `repro/run.sh` | repro runner (unmodified tree) |
| `repro/run2.sh` | post-fix runner (`[ENV=val ...] -- args`) |
| `repro/fa1.csv` | patched, `-fa 1 -p 2048 -n 0 -r 1`, rc=0 |
| `repro/moe1.csv/.err` | patched + `TOSH_OFFLOAD_MOE=1`, pp2048, rc=0, no assert |
| `repro/gate.csv` | patched, pp `16,128,256,448,512,1024,2048`, 7 rows, rc=0 |
| `repro/rc-after.txt` | `fa1/moe1/gate rc=0` |
| `text-default.txt`, `text-nopo.txt` | 35B prompt6k, 64 tokens, default vs `--no-op-offload` |
| `text-rc.txt` | both `rc=0` |

## Unmodified-tree repro matrix (before any source change)

All rows: `n_gpu_layers=0`, `backends=MTL,BLAS`, `no_op_offload=0`, D700 on card 1.

| Run | Shape | Result | Source |
|---|---|---|---|
| a1 | `-fa 1 -p 2048 -n 0 -r 1` | rc=0, 45.60 t/s | `repro/a1.csv` |
| a2 | same, repeated | rc=0, 45.66 t/s | `repro/a2.csv` |
| b1 | + `--no-op-offload 1` | rc=0, 28.72 t/s | `repro/b1.csv` |
| c1 | `-p 2048 -b 512 -ub 512` | rc=0, 45.96 t/s | `repro/c1.csv` |
| d1 | `-p 2048 -ub 256` | rc=0, 33.53 t/s | `repro/d1.csv` |
| e1 | `-p 4096 -n 0 -r 1` | rc=0, 43.95 t/s | `repro/e1.csv` |

No `GGML_ASSERT` in any `.err` (`grep -c GGML_ASSERT` = 0 for each).

## Where the abort happens (from the shipped-binary evidence)

`evidence/gates-beta8/out/pp-35b-host.err:22`:

```
/Users/sam/firellama/vendor/llama.cpp/ggml/src/ggml-backend.cpp:2193: GGML_ASSERT(id >= 0 && id < n_expert) failed
```

- That run: build `d81235049`/11429, `n_batch=2048 n_ubatch=512 n_gpu_layers=0 flash_attn=1
  no_op_offload=0`, 6 rows in `pp-35b-host.csv` (pp16 .. pp1024), abort on the pp2048 row.
- The vendor tree at `/Users/sam/firellama/vendor/llama.cpp` (dirty, 711 `tosh_dmoe` hits)
  carries the same assert text at 2193 with the same `id < 0 && tosh_dmoe_compact()` guard.
- `tosh_dmoe_compact()` is **default-on** (`tosh-moe/tosh-dmoe.cpp:429-432` in the worktree),
  so negative ids are skipped. The aborting id must therefore have been `>= n_expert`
  (an out-of-range expert id), not a negative host row.

## Why it does not reproduce on card 1

`repro/dbg-sched.err` (instrumented unmodified run, `-p 16`, card 1):

- line 1-2: `probed SIMD-group width = 64` on the D700.
- line 54: `simdgroup reduction = false`.
- `ggml/src/ggml-metal/ggml-metal-device.m:3071-3109`: `GGML_OP_MUL_MAT_ID` support requires
  `has_simdgroup_reduction` (3075) or `wave64_decode && ne[0] >= 32` plus a type allowlist.
  With `simdgroup reduction = false` on this device, the op stays off the GPU.
- Every MoE weight line shows `sid=2` (host split) and `buf=CPU_Mapped`, e.g.
  `WGT ffn_moe_gate-0 ... sid=2 ... sup0=1 off0=0` (960 such lines).
- `TRY ffn_moe_gate-0 b=0 batch=1 sup=1 offl=0 offmin` and `... batch=16 sup=0 offl=0 ...`
  (`dbg-sched.err:63-64`, `185-186`, `429-430`): the router matmul is *supported* but
  *offload refused*, so it runs on the host.
- No `dbg-badid` line ever fired, and the whole graph stayed one CPU split.

So on this card the offloaded `MUL_MAT_ID` never executes, which is why the assert path is
never reached. The shipped gate that aborted used card 0; the ticket's abort is therefore
device/build dependent.

## The applied fix

`ggml/src/ggml-backend.cpp`, `ggml_backend_sched_backend_id_from_cur`, around line 1161:

```cpp
// MoE with host weights stays on the host: the used-expert copy reads the router ids
// from whatever backend produced them, and on the discrete cards that read is not
// ordered after the router. TOSH_OFFLOAD_MOE=1 allows it.
static const bool moe_off = getenv("TOSH_OFFLOAD_MOE") != nullptr;
const bool off_ok = tensor->op != GGML_OP_MUL_MAT_ID || moe_off;
if (sched->op_offload && src_on_host && ggml_backend_buffer_is_host(src->buffer) && off_ok) {
```

- Only `GGML_OP_MUL_MAT_ID` is gated; dense `MUL_MAT` op offload is untouched.
- `TOSH_OFFLOAD_MOE=1` restores the old behaviour for comparison.
- Diff: `git diff` -> `+6 -1`, one file, `ggml/src/ggml-backend.cpp`.

This is the ticket's sanctioned fallback, **not** a verified root-cause fix. The root cause
(an id `>= n_expert` reaching the used-expert copy) was not isolated; see "Not done".

## After-fix verification

Built `build-fa` (`-j8`, targets `llama-bench llama-cli`):

| Binary | sha256 |
|---|---|
| `build-fa/bin/llama-bench` | `a4b9627016af46e041889943a47126480a1c40e9aab88dd9775d7822fdb1caa8` |
| `build-fa/bin/llama-cli` | `075b179f7fe2568a6bbb73b7b4f5a4e773c1008289ef1d0c8429756f0edcfc96` |

Before the fix the worktree binaries were `036d4816d954aae2...` / `eaa67e8cbf12dae...`.

| Run | Shape | Result | Source |
|---|---|---|---|
| fa1 | `-fa 1 -p 2048 -n 0 -r 1` | rc=0, 41.60 t/s | `repro/fa1.csv` |
| moe1 | fa1 + `TOSH_OFFLOAD_MOE=1` | rc=0, 45.45 t/s, 0 asserts | `repro/moe1.csv/.err` |
| gate | `-fa 1 -p 16,128,256,448,512,1024,2048 -n 0 -r 1` | rc=0, 7 rows | `repro/gate.csv` |

Gate row (patched, `-b 2048 -ub 512`, the shipped shape):

| pp | avg_ts |
|---|---|
| 16 | 15.48 |
| 128 | 33.09 |
| 256 | 38.04 |
| 448 | 42.02 |
| 512 | 43.65 |
| 1024 | 43.43 |
| 2048 | 42.12 |

`moe1` is the important one: with `TOSH_OFFLOAD_MOE=1` op offload is genuinely back on
(45.45 t/s, matching the unmodified baseline 45.60, versus 41.60 with the fallback active),
the offloaded `MUL_MAT_ID` path does run, and it still does not abort. The fallback therefore
does not hide the path; the path is simply not reachable on this card/build in a way that
produces an out-of-range id.

## Text check (`llama-cli`, 35B, `-ngl 0 -c 8192 -t 12 -fa on -st --temp 0 -s 1 -n 64`)

`prompt6k.txt` from `evidence/18/`.

| Run | rc | Output |
|---|---|---|
| default | 0 | `text-default.txt` |
| `--no-op-offload` | 0 | `text-nopo.txt` |

- Generated text **byte-identical**: 1604 chars each, `body equal: True`.
- Files differ only in the timing footer (`37.9 t/s` vs `26.0 t/s` prompt speed).
- `text-rc.txt`: `default rc=0`, `nopo rc=0`.

## DiagnosticReports

Newest entries before the first GPU run (`19:38` baseline) and at the end:

```
XeonLLM_2026-11-12-200559_Sams-Mac-Pro.cpu_resource.diag
XeonLLM_2026-11-12-193807_Sams-Mac-Pro.diag
codesign_2026-11-11-211515_Sams-Mac-Pro.diag
```

- No `*.panic`, no `*watchdog*`, no `*.gpuRestart` at any point.
- One new entry appeared during a build: `XeonLLM_2026-11-12-200559...cpu_resource.diag`.
  It is a CPU-limit report for the unrelated `/Applications/XeonLLM.app` (PID 35464),
  not a GPU incident, and not a stop condition.

## Not done / open

- **Root cause not isolated.** The aborting id is `>= n_expert` (the `id < 0` case is
  skipped by `tos_dmoe_compact()`), but which producer wrote it was not determined. The
  router path is `ffn_moe_argsort` (`src/llama-graph.cpp:2266`), and the copy that reads the
  ids is `ggml_backend_sched_compute_splits` (`ggml/src/ggml-backend.cpp:2161-2199`). The
  fix is the fallback, so the underlying id overflow remains.
- **Abort not reproduced on card 1.** Card 1's D700 reports `simdgroup reduction = false`
  (`repro/dbg-sched.err:54`), which keeps `MUL_MAT_ID` on the host. Card 0 was not tested:
  the ticket forbids touching the default GPU and only one heavy job may run at a time.
- The vendor tree `/Users/sam/firellama/vendor/llama.cpp` is dirty (uncommitted edits across
  many files) and could not be rebuilt or diffed against a clean base here.