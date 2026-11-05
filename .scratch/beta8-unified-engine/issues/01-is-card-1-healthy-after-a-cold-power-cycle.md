# Is card 1 healthy after a cold power cycle?

Type: task
Status: resolved
Mode: HITL (the user powers the Mac off and on)

## Question

On 2026-11-04 card 1 started failing basic op tests that it passed on 2026-11-03 with the same
binary (`test-backend-ops` sha256 `76a0d8b11e328d87`):

| op | card 1 | card 0 |
|---|---|---|
| ADD | 51/82 | 82/82 |
| MUL | 43/73 | 73/73 |
| RMS_NORM | 29/51 | 51/51 |
| SSM_CONV | 2/45 | 45/45 |

After a full power-off (at least 30 s), is card 1 back to every op passing?
- **Yes:** this was a transient driver or GPU state; record what preceded it.
- **No:** card 1 is failing hardware. Beta 8 plans one card plus the host, and the app must detect
  a failing card and leave it out.

**Checklist (user):** shut down, wait 30 s, power on. Then the agent runs `test-backend-ops`
(all ops) on each card and compares with the 2026-11-03 gate logs
(`evidence/gates-beta6/out/all-c*.log.gz`).

Today's card-1 results all become suspect until this resolves: beta7 tickets 01, 02, 03, 05 and 08.

## Answer (2026-11-05)

**Yes: transient.** After the user's cold power cycle (full shutdown, 30 s off), card 1 passes everything.

- The four failing ops, both cards: ADD 82/82, MUL 73/73, RMS_NORM 51/51, SSM_CONV 45/45.
- Full suite on card 1: **13983/13983 tests passed**, the same count as the 11-03 gate
  (`evidence/01/all-c1.log.gz`, 0 FAIL).
- Method: `GGML_METAL_DEVICE_INDEX=1 dist/XeonLLM.app/Contents/Resources/bin/test-backend-ops -b MTL0`;
  the device appears as MTL0 because the index pins slot 0 to physical card 1
  (`ggml-metal-device.m:1797-1823`, `MTLCopyAllDevices()[1]`). The same selector split failing card 1
  from passing card 0 on 11-04, so it does select a different card.
- No new `Kernel_*.gpuRestart` since 2026-11-04 23:31.

**What came before it:** the unbounded read-ceiling probe (long command buffer → GPU hang → CPU
machine check on PCIe bus 2 at 19:00 on 11-04), then 19 GPU resets between 19:12 and 23:31. A warm
reboot did not clear it; a cold power-off did.

**Follow-ups, done:** the app now checks every card at launch with a known-answer test and leaves a
failing one out (commit f512e24). The read-ceiling probe is bounded at 0.2 s per command buffer.
The card-1 numbers of 11-04 are still suspect and get re-measured in ticket 09.
