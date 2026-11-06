# 05: backport LFM3

Status: open (patch 0079 landed and verified on card 1 and the host; card-0 load and the card-1 timing cell remain)
Type: task
Spec: `../spec.md` (user story 19). Survey: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` §5 and shortlist item 5.

## Problem

LFM3-1.7B F16 does not load: `unknown model architecture: 'lfm3'`. Upstream added it after the
pin:
- #30874 (`84e66d032`), the shared LFM base;
- then #31252 (`19cce6919`), the LFM3 text model;
- #31431 adds tensor split (optional).

## What to build

One new patch under `patches/llama/model/`. It touches:
- `src/models/lfm-base.cpp`, `lfm3.cpp`, `lfm2.cpp` and `models.h`;
- `src/llama-arch.*`, `src/llama-model.cpp` and `src/llama-quant.cpp`;
- `gguf-py/`, as upstream does.

It must keep every existing patch applying, and keep the GPL headers.

## Gates

- `scripts/check-patch-series.sh` applies the series at the pin.
- The engine builds with `TOSH_NO_AVX2=1`, with 0 AVX2/FMA mnemonics.
- The orchestrator, after review:
  - LFM3-1.7B F16 loads on each card and on the host;
  - the release contract's stress cells pass;
  - `llama-bench -p 512 -n 128 -r 5 -fa 1` on card 1, with the method line.

## Comments

### 2026-11-07: patch 0079 complete, verified on card 1 and on the host

- The untracked 0079 held only the gguf-py hunks (174 lines). The engine source (lfm-base, lfm3,
  lfm2, models.h, llama-arch, llama-model, llama-quant) lived only in the vendor tree and the
  worktree `xeonllm-wt-clean`; both are byte-identical for those 8 files. 0079 is now both parts
  (791 lines, 10 files). `scripts/check-patch-series.sh d81235049`: 90 of 90 apply cleanly.
- Engine: vendor build-static (series + 0079 + 0080, AVX1: 0 vfmadd/vpbroadcast/vinserti128),
  llama-server sha256 `b932fb3ea81233ed`. Card 1 = `GGML_METAL_DEVICE_INDEX=1`, `TOSH_FA_AMD=1`.
- Text, `/v1/chat/completions` "What is the capital of France? Answer in one sentence.",
  temperature 0, max_tokens 160, -c 4096 --jinja:
  - card 1, `-ngl 99`: content "The capital of France is Paris.", finish `stop`;
  - host, `-ngl 0`: the same content; reasoning plus content **byte-identical** to card 1.
- The card cell really ran on the card: llama-bench lists the backend as `MTL,BLAS`, and while it
  decoded one accelerator read 98-99 % "Device Utilization" while the display card stayed at its
  idle 3-8 % (`evidence/09/lfm3-card1-util.txt` in beta8).
- Decode, observation only (not the gate cell): llama-bench `-ngl 99 -p 0 -n 128 -r 2 -fa 1`, card 1,
  22.98 ± 0.05 tok/s (N=2, no warmup discarded); the server reported 22.3 tok/s on card 1 and
  12.6 tok/s on the host for the 160-token answer (N=1 each, a concurrent CPU build was running).
- Still owed: the load on card 0 (card 0 is in use by ticket 08's run); the gate cell
  `llama-bench -p 512 -n 128 -r 5 -fa 1` on card 1 with an idle machine.
