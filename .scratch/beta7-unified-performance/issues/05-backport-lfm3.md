# 05: backport LFM3

Status: ready-for-agent
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
