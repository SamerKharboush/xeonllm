# What clock headroom do the D700s and the Xeon have on macOS, and at what risk?

Type: research
Status: resolved
Scope: research only (the user's choice). Nothing here changes the app or the machine.

## Question

On a Mac Pro 6,1 under macOS 15, what is known about the following, from primary sources (Apple
docs, AMD specs, kext sources, published measurements on this model)?
- raising or holding the D700 core/memory clocks or power states;
- the Xeon E5-2697 v2's turbo behaviour;
- thermal limits (the shared thermal core);
- the risks of each.

Include:
- the documented clocks (D700 850 MHz core, 1370 MHz memory?);
- whether any tool can change them on macOS without a custom kext;
- whether the card already throttles under sustained load. A measurement is possible: the
  read-ceiling probe over a long soak, in short command buffers.

Answer whether any of it is worth a beta 8 ticket at all. Output:
`.scratch/beta8-unified-engine/research/04-clock-headroom.md`.

## Answer

**No clock, power-limit or fan ticket for beta 8.**
- The D700 runs at 850 MHz core and 1370 MHz memory under load (the driver's own counters).
- No public macOS control exists for these GPUs. The AMD kexts are closed, and the injection
  tables documented online cover later generations only.
- The Xeon's multiplier is locked.
- A memory overclock is the only lever that matches this read-bound workload, and it is the
  riskiest: GDDR5 errors give silent wrong answers before they hang the card, and a hang of card 0
  panics the Mac.

**One high-priority ticket instead: card health at app start.**
- Count GPU-reset reports per PCIe address.
- Run a tiny known-answer test (ADD, MUL, RMS_NORM) on each card, in one short command buffer with
  a timeout.
- Map each Metal device to its PCIe address (`registryID`).
- Leave a failing card out, behind an injected-fault override shown to take effect.

**Optional:** log the driver's clock, temperature and fan counters once a second during existing
benches, and record them in the method line.

**Verified by the orchestrator:** `/Library/Logs/DiagnosticReports` holds 19 `*.gpuRestart`
reports on 2026-11-04, from 19:12:32 to 23:31:22, and one on 2026-11-02 at 19:04. The 19:00
panic before them was a CPU machine check whose address is in PCIe config space (bus 2).

Full findings, with UNVERIFIED marks: `research/04-clock-headroom.md`.
