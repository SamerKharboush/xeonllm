# What clock headroom do the D700s and the Xeon have on macOS, and at what risk?

Type: research
Status: open
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
