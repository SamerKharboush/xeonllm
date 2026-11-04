# 06: a dense model across both cards and RAM answers zeros (tracks ticket 68)

Status: needs-triage
Type: task
Spec: `../spec.md` (user story 20). Survey: `.scratch/firellama-maxperf/evidence/engine-survey-2026-11-04.md` §3.7 and shortlist item 6.
Tracks: `.scratch/firellama-maxperf/issues/68-*`

## Problem

A dense model split across both cards, with the rest on the host, answers zeros. This was seen
with the 27B Q6_K, cells two24/two28 in
`the-dense-27b-across-host-one-card-and-both-cards-2026-10-22.md`. It blocks the one
configuration that uses both cards and RAM for one dense model.

## What to do

- Bisect with the ticket 71 / `moe/0053` method: switch each fusion off by environment.
- Then look at the mixed-placement path in `src/llama-graph.cpp` and the scheduler.

## Gate

- 27B Q6_K, cells two24/two28: text identical to the host reference for 400 tokens.
- N=4 per cell, with both cards' buffers in the log.

## Comments
