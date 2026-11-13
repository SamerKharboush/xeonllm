# 25e — Ternary at -ngl 0: does the 0082 op-offload rule act on the prompt mat-muls?

Measurement only. No source edits, no build, no commits. One server at a time, foreground,
-ngl 0 only, ports from the script's free-port picker (user's llama-server on 127.0.0.1:8080,
pid 747, never queried or touched).

Runs (all `scripts/stress-release.sh $B /Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf`,
APPLOG=gates-beta8/out/set/$S.applog, cells band16 band300 band1100):

| run | env / flags | out dir |
|---|---|---|
| nopo | `MODES=ngl0nopo` → `-ngl 0 --no-op-offload` | `nopo/` |
| mb | `MODES=ngl0`, `GGML_OP_OFFLOAD_MIN_BATCH=100000` | `mb/` |
| base | `MODES=ngl0` (beta 8 as shipped) | `base/` |
| nopo2 | repeat of nopo, to catch server args + time drift | `nopo2/` |

## Controls took effect

(a) nopo, server command line saved in `nopo-cmd.txt` (ps of the live server pid):

```
.../bin/llama-server -ngl 99 -c 32768 -t 12 -fa auto --ubatch-size 128 --batch-size 128 --load-mode none --jinja --no-reasoning-preserve --metrics --cache-ram 2048 --cache-reuse 256 --parallel 1 --split-mode layer -n 2048 -m /Users/sam/models/Ternary-Bonsai-2-27B-PQ2_0.gguf --host 127.0.0.1 --port 53534 -ngl 0 --no-op-offload
```

(base's, `base-cmd.txt`, ends `-ngl 0` with no `--no-op-offload`; both servers logged the
deprecated duplicate `-ngl` warning and used the last value, `-ngl 0`.)

(b) mb, `mb-env.txt` — the only line of the server's environment captured, while it ran:

```
GGML_OP_OFFLOAD_MIN_BATCH=100000
```

## Result: the offload explains band300, and nothing else

`compare.txt` (produced by `cmp.py`, same offset rule as ternary-all5/cmpall.py):

| run | cell | len | vs beta.7 | vs beta 8 |
|---|---|---|---|---|
| nopo | band16 | 309 | IDENTICAL | IDENTICAL |
| nopo | band300 | 274 | IDENTICAL | diff@226 (len 274 vs 276) |
| nopo | band1100 | 255 | IDENTICAL | IDENTICAL |
| nopo2 | band16 | 309 | IDENTICAL | IDENTICAL |
| nopo2 | band300 | 274 | IDENTICAL | diff@226 (len 274 vs 276) |
| nopo2 | band1100 | 255 | IDENTICAL | IDENTICAL |
| mb | band16 | 309 | IDENTICAL | IDENTICAL |
| mb | band300 | 274 | IDENTICAL | diff@226 (len 274 vs 276) |
| mb | band1100 | 255 | IDENTICAL | IDENTICAL |
| base | band16 | 309 | IDENTICAL | IDENTICAL |
| base | band300 | 276 | diff@226 (len 276 vs 274) | IDENTICAL |
| base | band1100 | 255 | IDENTICAL | IDENTICAL |

The difference is one character at 226:

- beta.7 / nopo / mb: `... Likely blue. Need be terse. ...`
- beta 8 / base:     `... Likely "blue". Need be terse. ...`

nopo vs mb: all three cells IDENTICAL. mb vs base: band300 DIFFERS, others IDENTICAL.

## Cell times (`cells-times.txt`, seconds for the 64-token answer)

| run | band16 | band300 | band1100 |
|---|---|---|---|
| nopo | 159.7 | 234.7 | 414.1 |
| mb   | 159.5 | 232.8 | 416.7 |
| base | 135.7 | 161.3 | 236.0 |
| nopo2 | 160.4 | 233.6 | 419.4 |

Both controls are ~24–78% slower than base on every cell, so both did take the prompt off the
cards; base is the only fast one, i.e. the only one that offloaded.

## Reading

At -ngl 0 the shipped beta 8 engine does offload the prompt mat-muls to a D700 (base, ~236 s at
band1100). Removing that offload — by `--no-op-offload` (nopo) or by a threshold above the batch
(`GGML_OP_OFFLOAD_MIN_BATCH=100000`, mb) — reproduces beta.7's band300 text byte for byte and
leaves band16/band1100 unchanged. band1100 never differed between the releases, so it carries no
signal either way; band16 does not either.

So the core/0082 change (gated GPU offload of large-batch MUL_MAT whose weights are on a host
backend) is the cause of the band300 divergence at -ngl 0, confirmed by two independent controls
that both disable it, one by flag and one by threshold.

## Safety

`diagreports-first.txt` (39 names, taken before the first run) vs `diagreports-after-*.txt`
taken after mb, base and nopo2: 39 names each, `comm -13` empty — no new panic, watchdog or
gpuRestart name. The pre-existing `*.gpuRestart`/`*.panic`/`watchdog.spin` names are from
2026-11-06/07/10/11 and appear in the baseline listing. No build, no stray server left
(`current.pid` in each OUT is the dead server's pid; the run's `kill_server` reaped it).

Files: `nopo/`, `nopo2/`, `mb/`, `base/` (server logs, cells.tsv, answers.json), `nopo-cmd.txt`,
`base-cmd.txt`, `mb-env.txt`, `cells-times.txt`, `compare.txt`, `cmp.py`, `cap.sh`,
`diagreports-*.txt`.