# Is card 1 healthy after a cold power cycle?

Type: task
Status: open
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
