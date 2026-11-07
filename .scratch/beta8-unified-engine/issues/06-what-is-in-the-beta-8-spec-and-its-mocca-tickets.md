# What is in the beta 8 spec, and how is it cut into Mocca tickets?

Type: grilling
Status: resolved (2026-11-07)
Blocked by: 05, 04

## Question

Write the beta 8 spec from the decisions so far, and cut it into implementation tickets Mocca can
run blind. Each ticket must name:
- the files;
- the test seam;
- what not to run (the safety rules);
- the measured gate;
- the report contract.

Which tickets go to Mocca, and which stay with the orchestrator (GPU gates, anything that runs a
model)?

## Answer

`../spec.md` and tickets 10-17. Mocca: 10, 11, 13 (code), 14 (code), 17 (kernel, after the profile). Orchestrator: every GPU gate, 12, 15, 16, the 17 profile.
