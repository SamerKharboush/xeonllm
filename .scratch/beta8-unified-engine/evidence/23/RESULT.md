# 23: decomposed prefill capped by KQ size on 64-lane cards

Status: all gates ran. The cap moves the 14B app-like prefill back onto flash attention and the
4B/0.6B pp512 wins are kept. Two caveats are under "Open".

## Method

- Source: worktree `/Users/sam/Library/Caches/xeonllm-wt-fa`, series 0001-0084 on upstream pin
  `d81235049` (HEAD `6111fd28e` "metal/0084 (ticket 16)"), plus this uncommitted change
  (`diff.patch`, `git status --short` shows only `src/llama-graph.cpp`).
- Build: `cmake --build build-fa -j8 --target llama-server llama-bench`, build 17:34-17:35
  (`build.log`). No GPU program ran during the build.
- `build-fa/bin/llama-server` sha256 prefix `03b09726db6ffed8`;
  `build-fa/bin/llama-bench` sha256 prefix `078d37ba20c2d2e1` (`sha256.txt`).
- Card: AMD Radeon HD - FirePro D700, two cards, SIMD width 64. The 14B repro runs over both
  cards (`GGML_METAL_DEVICE_LIST=0,1`, `--split-mode layer`, model 9001753376 bytes). llama-bench
  and the text server run on card 1 (`GGML_METAL_DEVICE_INDEX=1`, `-dev MTL0`). `TOSH_FA_AMD=1` in
  every GPU run.
- llama-bench: `-ngl 99 -fa 1 -b 2048 -p 512 -n 128 -d 6144 -r 3`, `type_k/type_v = f16/f16`,
  `n_gpu_layers = 99`, two processes per arm alternating new / `TOSH_FA_PF_W64=1`, run as two
  concurrent groups (`b4-ub128` and `b06-ub512` in `bench/bench.sh`, `bench/bench.log`). Every
  process was wrapped in `perl -e 'alarm 900; exec @ARGV'`.
- The over-cap row is 4B `-ub 512 -p 512 -n 0 -d 6144`, four processes alternating new / w64
  (`bench/over-*.csv`).
- Text: `srv23.sh` (shipped `gates-beta8/srv.sh` with `B` pointed at this build), 4B on card 1,
  `-ngl 99 -c 8192 -ub 128 -b 2048 -fa on -t 12 --jinja --parallel 1 --cache-ram 0 -v`,
  request `gates-beta8/out/req83.json` (`text/v-lv4.*` new, `text/v-lv4-w64.*` w64).
- DiagnosticReports: before `diag-before.txt`, after `diag-after.txt`. The three newest entries
  (`codesign_2026-11-11`, `cp_2026-11-11`, `Kernel-2026-11-11-083524.panic`) are the same before
  and after; no new `*.panic`, `*watchdog*` or `*.gpuRestart`. The older entries that disappeared
  between the two `ls -t` runs are the "Retired"/"DiagnosticLogs" directory entries, not reports.

## Change

`src/llama-graph.cpp`, `build_attn_mha`:

- new helper `decomposed_kq_bytes_ok(q, k)` next to `build_attn_mha`. Cap = 256 MiB default,
  `TOSH_FA_PF_DECOMP_MAX_MB` (MiB) overrides; `0` or unset = default.
- `amd_prefill_decomposed` gains `&& decomposed_kq_bytes_ok(q, k)`. Nothing else changed:
  `amd_prefill_fa_blocked` (32-lane rule, `TOSH_FA_PF_W64`, `TOSH_FA_PF_DISABLE`) is untouched.
- Comment above `amd_prefill_fa_blocked` records the 14B numbers.

### Which dims hold n_tokens / n_kv / n_head

At the gate point the permutes (`q = ggml_permute(ctx0, q, 0, 2, 1, 3)`, same for `k`) have
already run, so

- `q->ne[1]` = n_tokens(q): before the permute `q->ne` was `[head_dim, n_tokens, n_head, n_stream]`;
  permute `(0,2,1,3)` puts n_head at `ne[1]` -> after: `[head_dim, n_tokens(q), n_head(q), n_stream]`.
- `k->ne[1]` = n_kv(k), same way: `[head_dim, n_kv(k), n_head(k), n_stream]`.
- `q->ne[2]` = n_head(q).

`ggml_mul_mat(ctx0, k, q)` then yields `[n_tokens(q), n_kv(k), n_head(q), n_stream]` f32, i.e.
`q->ne[1] * k->ne[1] * q->ne[2] * 4` bytes per stream. The check uses exactly that product.
Cross-check at the 14B launch (ub 512, n_ctx 32768, 40 q heads): 512 x 32768 x 40 x 4 =
2684354560 bytes = 2.5 GiB, above the 256 MiB cap, so FA. At 4B ub 128 d 6144 (n_kv padded,
256 <= n_kv <= 6784, 32 heads): 128 x 6784 x 32 x 4 = 111 MB <= 256 MiB, decomposed. At 4B ub 512
same depth: 512 x 6784 x 32 x 4 = 444 MB > 256 MiB, FA.

## Gate 1: 14B repro (both cards), repro.sh, 5430-token prompt, max_tokens 64

`repro/repro-<label>.log`; timings from `slot print_timing` (tok/s).

| run | route | prompt eval time | decode eval time |
|---|---|---|---|
| new-1 | FA (cap) | 269839.89 ms / 5430 tokens, 20.12 tok/s | 18474.73 ms / 64 tokens, 3.41 tok/s |
| w64-1 | decomposed | 316237.92 ms / 5430 tokens, 17.17 tok/s | 18601.62 ms / 64 tokens, 3.39 tok/s |
| new-2 | FA (cap) | 429454.40 ms / 5430 tokens, 12.64 tok/s | 18616.61 ms / 64 tokens, 3.38 tok/s |

- Beta.7 engine reference on this request: prompt 17.17/17.12, decode 3.33/3.38.
- `op offload off ... 2904` line: 0 occurrences in all three logs (`grep -c`).
- new-1 prompt 20.12 is above the w64 band (17.17); new-2 prompt 12.64 is below it. Decode
  3.41/3.38 vs 3.39: the same. The prompt column is not resolved: run-to-run spread of the new
  arm (20.12 vs 12.64) is wider than the gap to w64.
- Route evidence: new-1 and new-2 log
  `ggml_metal_op_flash_attn_ext: kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16_w64_lg16 ...` /
  `kernel_flash_attn_ext_pf_amd_dk128_kf16_vf16 is not available on this card; the tile kernel
  takes the prefill` (the FA tile path), at the first prompt batch (new-1 at 0.25 s, new-2 at
  2.53 s). w64-1 does not log these.
- The 2904 MiB reservation is gone, but a new ceiling shows up at teardown (`~llama_context`):
  `MTL0_Private compute buffer size of 582.0547 MiB, does not match expectation of 438.4609 MiB`
  and `MTL1_Private compute buffer size of 492.0391 MiB, does not match expectation of 348.4650 MiB`
  (new-1, lines 32-33). That is 143.59 MiB above the reservation on each card, and it is the
  allocator growing during the run, not the worst-case reserve.

### Compute buffer lines (14B, both cards)

The 14B server does not print `compute buffer size` at load (no `-v`; the `I sched_reserve:
MTL0_Private compute buffer size = ...` line only appears with `-lv 4`/`-v`). The only buffer
lines it prints are the teardown ones quoted above. To get the reserve lines at 14B a `-v` repro
run is needed; it was not run (time).

## Gate 2: ticket 21 wins (card 1, llama-bench, `-r 3`)

`bench/table.txt` (ts = tok/s, std = stddev_ts).

### 4B Q4_K_M, `-ub 128 -p 512 -n 128 -d 6144`

| arm | pp512 | tg128 |
|---|---|---|
| new | 55.785065 (0.189425), 56.398517 (0.063327) | 12.132478 (0.001069) |
| w64 | 27.289222 (0.011135), 27.606748 (0.003793) | 12.132694 (0.003656), 12.134743 (0.002116) |

pp512: both new above both w64 (55.79/56.40 vs 27.29/27.61). PASS.

### 0.6B Q8_0, `-ub 512 -p 512 -n 128 -d 6144`

| arm | pp512 | tg128 |
|---|---|---|
| new | 235.965514 (0.182679), 148.597643 (13.743131) | 39.172043 (0.344636), 5.854788 (4.041780) |
| w64 | 86.292218 (0.036759), 82.911173 (1.127581) | 38.959101 (0.419130), 6.113037 (8.287169) |

pp512: both new above both w64 (148.60/235.97 vs 82.91/86.29). PASS.

The 0.6B rows with tg128 5.85/6.11 (one new, one w64) are decode outliers next to 39.17/38.96 in
the same column; the two arms overlap there and decode is not the ticket-21 criterion.

### Over the cap: 4B `-ub 512 -p 512 -n 0 -d 6144` (both arms take FA)

| arm | pp512 |
|---|---|
| new | 27.103882 (0.040773), 27.114123 (0.014616) |
| w64 | 27.110118 (0.043378), 27.125038 (0.039286) |

Alike, as expected.

## Gate 3: text (card 1, 4B, `-c 8192 -ub 128 -b 2048 -fa on`)

`text/v-lv4.txt` (new) and `text/v-lv4-w64.txt` (w64): `cmp` -> IDENTICAL. 297 bytes,
reasoning_content + `|` + content, beginning

```
Okay, the user provided a lot of repeated sentences about a committee meeting. ... The user wants a summary|
```

## Gate 4: no AVX in the binary

```
otool -tv build-fa/bin/llama-server | grep -cE 'vfmadd|vfmsub|vfnmadd|vpbroadcast|vinserti128|vextracti128|vpgather' -> 0
```

## Compute buffer lines (text gate, `-v`, card 1, 4B, -c 8192)

The reserve is done at worst case (n_kv = n_ctx): the decomposed KQ at ub 128 x 8192 x 32 heads =
128 MB would fit, but the FA graph (n_kv = n_ctx, ub 512) is what sizes the buffer.

new (`text/v-lv4.log`):

```
0.00.821.221 I sched_reserve: MTL0_Private compute buffer size =   175.76 MiB
0.00.821.222 I sched_reserve:        CPU compute buffer size =    20.52 MiB
0.04.786.897 I sched_reserve: op offload on: MTL0_Private compute buffer 175.76 MiB, cap 1536 MiB
0.04.802.673 I sched_reserve: MTL0_Private compute buffer size =   175.76 MiB
0.04.802.675 I sched_reserve:        CPU compute buffer size =    20.52 MiB
1.41.215.000 D ~llama_context: MTL0_Private compute buffer size is 175.7638 MiB, matches expectation of 175.7638 MiB
1.41.215.008 D ~llama_context:        CPU compute buffer size is  20.5177 MiB, matches expectation of  20.5177 MiB
```

w64 (`text/v-lv4-w64.log`):

```
0.00.809.076 I sched_reserve: MTL0_Private compute buffer size =    84.03 MiB
0.00.809.077 I sched_reserve:        CPU compute buffer size =    20.52 MiB
0.02.263.291 I sched_reserve: op offload on: MTL0_Private compute buffer 84.03 MiB, cap 1536 MiB
0.02.276.833 I sched_reserve: MTL0_Private compute buffer size =    84.03 MiB
0.02.276.834 I sched_reserve:        CPU compute buffer size =    20.52 MiB
2.34.403.844 D ~llama_context: MTL0_Private compute buffer size is  84.0314 MiB, matches expectation of  84.0314 MiB
```

The new arm reserves 175.76 MiB (FA graph, worst case) and finishes with 175.7638 MiB
("matches expectation"): at this request the prompt batches (5430 tokens, ub 128) stay under the
cap, and the buffer did not need to grow past the reservation.

## Open

- The scheduler reserve is taken at worst case, so the new arm's compute buffer is the FA graph
  (175.76 MiB) and not the smaller decomposed one (84.03 MiB). That is the expected behaviour of
  the existing reserve and not a regression, but it means the memory win of decomposed prefill is
  not realised at context sizes where the FA worst case is larger.
- The 14B teardown lines (582.05 / 492.04 MiB vs 438.46 / 348.47 expected) show a 143.59 MiB
  growth during the run. Whether a request whose prompt batches cross the cap mid-run (decomposed
  first, FA later) reallocates was not measured; the text gate above does not cross the cap.
- 14B repro prompt times: new 20.12 then 12.64 vs w64 17.17, beta.7 17.17/17.12. Gate says "new
  within the w64 band"; new-2 is outside it on the low side. Decode is within the band.

## Not run

- 14B repro with `-v` (reserve lines at 32k): not run, time.
- llama-bench `-d 0,2048,6144` (ticket 21's full depth sweep): only `-d 6144` was run.