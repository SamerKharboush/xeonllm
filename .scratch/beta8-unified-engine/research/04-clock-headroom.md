# Research 04: clock headroom on the D700s and the Xeon, and its risk

Answers `issues/04-what-clock-headroom-do-the-d700s-and-the-xeon-have-on-macos.md`.
Scope: research only. Nothing on the machine was changed. No GPU load, stress test or benchmark was run.
The only things run were read-only queries (`ioreg`, `sysctl`, `pmset -g`, `system_profiler`,
`nvram -p`, `csrutil status`, `kextstat`), plus reads of the existing crash reports in
`/Library/Logs/DiagnosticReports/`. All were taken on 2026-11-04/05.

## Verdict (read this first)

1. **Raising D700 or Xeon clocks: not worth a ticket.** No documented tool raises Southern
   Islands (Tahiti) clocks on macOS. The only route would be injecting undocumented `PP_*`
   PowerPlay properties through OpenCore, and nobody has shown that works for SI on macOS
   (UNVERIFIED either way). The Xeon multiplier is locked (Intel ark: Turbo Boost 2.0, no
   unlocked-multiplier SKU). Decode here is bound by memory reads, so only a memory overclock
   could help, and the GDDR5 is on a card that is currently failing. The user has also ruled
   this research-only.
2. **Detecting a failing card at app start: worth a beta 8 ticket, and it should be high
   priority.** This machine's own logs pin the 2026-11-04 faults to one physical card: the
   headless D700 at PCIe 2:0:0, slot 1. See §4.
3. **Measuring sustained-load throttling: worth no more than a small add-on.** Log the
   driver's own clock, temperature and fan counters next to bench rows that already run. Do
   not build a dedicated soak test. Nothing observed so far shows throttling, but nothing has
   tested for it either (§3).

## 1. Documented D700 clocks and power states

| Fact | Value | Source |
|---|---|---|
| Silicon | Tahiti XT, PCI device ID 0x6798, 2048 stream processors, 384-bit GDDR5, 6 GB | Apple tech specs [A1]; `system_profiler SPDisplaysDataType` on this machine (Device ID 0x6798, VBIOS 113-C3861XA-028 / XB-028) |
| Apple's rated figures | 264 GB/s memory bandwidth, 3.5 TFLOPS per card | Apple [A1] |
| Core clock under load | **850 MHz** | driver counter `PerformanceStatistics."Core Clock(MHz)"`, read on this machine under load (`firellama-maxperf/evidence/what-the-machine-actually-uses-2026-10-20.md`, `the-second-d700-was-never-registered-2026-10-20.md`) |
| Memory clock under load | **1370 MHz** (GDDR5, so 5.48 Gb/s per pin) | the same driver counter, `"Memory Clock(MHz)"` |
| Base clock | 650 MHz ("base"), with 850 MHz as the boost state | AnandTech Mac Pro review [S1], seen only through search snippets, because anandtech.com no longer serves the article. UNVERIFIED against the original. |
| Idle | 300 MHz core / 150 MHz memory. An intermediate 450 MHz core has also been seen. | this machine, `ioreg`, 2026-11-05 (both cards idle, 63-67 C, fan 33-36 %) and 2026-10-20 |

The spec numbers check out by arithmetic, not by measurement: 2048 x 2 FLOP x 850 MHz = 3.48 TFLOPS,
and 384 bit x 5.48 Gb/s / 8 = 263 GB/s. Both match Apple's rated figures, so 850/1370 is the
top state Apple rates the card at. The measured read ceiling (204-206 GB/s per card, beta 7 ticket 02)
is a separate quantity. It is quoted here as a measurement, not as a fraction of Apple's figure.

**Power-management stack (this machine, ioreg, read-only):**
- Kexts: `AMDRadeonX4000` 4.8.101 (CFBundleVersion 4.0.8), `AMD7000Controller`, `AMDFramebuffer`,
  `AGPM` 137, `ACPI_SMC_PlatformPlugin`. These are Monterey-era legacy GCN kexts, root-patched in by
  **OpenCore Legacy Patcher 2.5.1**. macOS 15.8 is not supported on a MacPro6,1: Apple lists
  Monterey as its newest OS [A2].
- AGPM's machine table for `MacPro6,1`: GFX1 and GFX2 each have `min-power-state=0`,
  `max-power-state=15` and `Heuristic ID = -1`. The values come from Apple's AGPM; what each state
  means is not documented (UNVERIFIED).
- AMD PowerPlay properties on both cards: `PP_PowerPlayEnabled=1`, `PP_DisablePowerContainment=0`,
  `PP_DisableCAC=0`, `PP_DisableDTE=1`, `PP_ActivitySamplingInterval=1000`,
  `PP_HighSamplingInterval=200000`, `PP_SISLANDSVotingRightsClients=12583475`. So power containment
  (the PowerTune TDP clamp) and CAC activity estimation are **on**, and the digital temperature
  estimator is **off**.
- These names map one to one onto the open Linux driver for the same silicon. `radeon/si_dpm.c`
  implements `si_enable_power_containment`, `si_populate_smc_tdp_limits`, CAC tables and DTE
  tables, and it lists device ID `0x6798` among the Tahiti PowerTune cases [K1]. PowerTune on
  Tahiti has 3 or 4 DPM states and can cut clocks *within* a state when it nears the power limit.
  AMD exposes only the base states [S2]. So a card that reports "850 MHz" could still be clamped
  between samples. The driver's 1 s activity sampling interval sets how fine-grained any clock
  reading from ioreg can be.

## 2. Can a user change them on macOS?

- **Metal / public API:** no. MTLDevice has no performance-state or clock API on macOS. (I found no
  Apple document that offers one; absence of evidence only.)
- **Apple tools:** none that set clocks. `pmset` exposes CPU thermal notifications only
  (`pmset -g therm`: `CPU_Speed_Limit=100`, `CPU_Scheduler_Limit=100`, "No thermal warning
  level has been recorded").
- **AMD/Apple kext source:** not public. The AMD GPU kexts are closed. The only public reference
  for this silicon's power logic is the Linux `radeon` driver [K1].
- **PowerPlay-table injection (`PP_PhmSoftPowerPlayTable` through OpenCore/WhateverGreen):**
  documented and used for Polaris, Vega and Navi only. The `upp` tool lists Polaris, Vega,
  Radeon VII and Navi 10/12/14 [S3, S4]. **Nothing documents it for Southern Islands on
  macOS (UNVERIFIED that it works at all).** Even on Linux, SI PowerPlay was a late,
  experimental add [S5], and `si_dpm.c` offers a TDP-limit adjustment, not a clock override
  [K1].
- **What this machine would allow:** SIP is partly off (`csr-active-config 03080000`, kext
  signing off, filesystem protections off). So property injection *could* be attempted. That
  is exactly why this note records it: the door is open, and nothing says what is behind it.
- **Boot Camp/Windows tools (Afterburner and similar):** I found no published D700
  overclock with a method (UNVERIFIED). That route is off-platform anyway.

## 3. Xeon E5-2697 v2 and the shared thermal core

| Fact | Value | Source |
|---|---|---|
| Base / max turbo | 2.70 GHz / 3.50 GHz, Turbo Boost 2.0 | Intel ark [I1] |
| TDP / Tcase max | 130 W / 86 C | Intel ark [I1] |
| ISA | AVX (no AVX2 or FMA; F16C is in CPUID) | Intel ark [I1]; the map |
| Turbo bins (+100 MHz steps, 12 active cores down to 1) | 3/3/3/3/3/3/3/4/5/6/7/8, so **3.0 GHz with all cores active**, 3.5 GHz with one | Marco Arment, citing Intel's tables [S6]. Intel's own spec update holds the primary table and was not fetched (UNVERIFIED at the primary). |
| macOS view | `hw.cpufrequency` reports a fixed 2.7 GHz (nominal). `machdep.xcpm.mode=0`: P-states run through `ACPI_SMC_PlatformPlugin`, not XCPM. `machdep.xcpm.cpu_thermal_level=0`, `gpu_thermal_level=0` | this machine, `sysctl` |
| Chassis | One heat sink (the "thermal core") is shared by the CPU and both GPUs, cooled by one fan. Rated for 450 W maximum continuous power. | Apple [A1]; iFixit teardown [S7] |

**Published measurements on this chassis:**
- AnandTech [S1], via a forum summary (UNVERIFIED against the original): the CPU began to throttle
  only under a combined power virus, at 437 W average and 463 W peak at the wall. The same summary
  reports no CPU or GPU throttling in real workloads.
- Crystalidea [S8] (Mac Pro 2013, E5-2667 v2 and D500, Windows, powerMax AVX for 10 min, 22 C
  ambient): CPU 83 C with the stock fan at about 1200 RPM. The stock curve does not ramp until the
  CPU passes 80 C. A fixed 1500 RPM cut CPU and GPU temperatures by about 9 C. No throttling was
  reported. This is a different CPU and GPU, so it is an observation about the chassis, not about
  this machine.
- Forum: about 95 C CPU and 97 C GPU under FurMark plus Prime [S9]. Anecdotal, UNVERIFIED.

**What that means here:** the decode workloads load one GPU plus some CPU threads, which is far
below the 437-463 W at which throttling was reported. **No throttling has been observed on this
machine, but none has been looked for.** The evidence:
- 850 MHz / 98-128 % activity / 69 C at full decode (2026-10-20);
- repeated 1.5 s read-ceiling soaks agree to within about 1 GB/s (204.4-206.1 GB/s on card 1,
  `beta7-unified-performance/evidence/02/readceiling-card1.txt`).

Neither run was long enough to heat-soak the core. Under shared cooling, CPU threads raise GPU
temperature, so a hybrid CPU+GPU schedule (the beta 8 aim) is the case most likely to throttle.

## 4. D700 failure modes, and what this machine shows

**Known fleet issue:** Apple ran a repair extension program for Late 2013 Mac Pros with D500 or D700
cards built between 2015-02-08 and 2015-04-11 [S10]. The symptoms were distorted or no video,
instability, freezes, restarts and failure to boot. Both cards were replaced, and the program ran to
2018-05-30. These are press reports of Apple's internal notice. I found no live Apple page for it
(UNVERIFIED at the primary). Owner reports [S11] describe the same chain: GPU hang, then "Trying to
restart GPU", then a kernel panic naming `AMDRadeonX4000`. This is anecdotal.

**This machine's own record (read-only, `/Library/Logs/DiagnosticReports/`):**

| When | Report | What it names |
|---|---|---|
| 11-02 19:04 | gpuRestart | PCIe **6:0:0** (slot 2, drives the display), WindowServer, Compute1 |
| 11-03 08:41, 13:11 | panic | userspace watchdog: WindowServer (the oversized-model-on-the-display-card case in memory) |
| 11-04 09:14 | panic | spinlock timeout (the 28 GB `-ngl 99` case in memory) |
| **11-04 19:00** | panic | **CPU Machine Check:** `IA32_MC20_STATUS=0xFE200000000C110A`, `IA32_MC20_ADDR=0xE02003C0`; `IA32_MC3_STATUS=0xF200000000800400` |
| **11-04 19:12 to 23:31** | **19 gpuRestart** | **all on PCIe 2:0:0**: 18 from `test-backend-ops`, 1 from `llama-server`. Channel GFX, apart from one Compute1 |

Mapping, from `ioreg` and `system_profiler`:
- PCIe 2:0:0 is `GFXA@2/GFX1`, Slot-1, "No Display Connected". That is the headless card.
- PCIe 6:0:0 is `GFXB@3/GFX2`, Slot-2, which carries WindowServer's VRAM.
- Earlier evidence pinned the headless card to Metal index 1 (`GGML_METAL_DEVICE_INDEX=1`). So
  "card 1" in the ticket is very probably slot 1, bus 2. Confirm this by `MTLDevice.registryID`
  before relying on it.

Decoding the MCA (my inference, not vendor-confirmed):
- The panic gives `pcie_cfg_base=0xe0000000`. Under the standard PCIe ECAM layout,
  `0xE02003C0` is bus 2, device 0, function 0, config offset 0x3C0. **So the machine check
  addresses the headless D700's own config space.**
- `MC3` MCACOD `0x0400` is Intel's "internal timer error" encoding (Intel SDM vol. 3B, MCA
  error codes; not fetched here, so UNVERIFIED).
- **The GPU reset storm on that card starts 12 minutes after this panic.**
- That pattern fits a card that stopped answering on the PCIe bus, a hardware or link fault rather
  than a software state. It does not prove one. Issue 01 (a test after a cold power cycle) decides
  it.

Plausible causes, all UNVERIFIED for this unit:
- the known 2015 batch defect;
- ageing GDDR5 or solder (the card is about 11 years old);
- thermal stress from repeated hang-and-reset cycles;
- a root-patched kext stack running on an OS Apple never qualified for this card.

## 5. Risks of each idea

| Idea | Possible gain | Risk |
|---|---|---|
| Raise core clock (PP injection) | little: decode reads memory | No working method on SI is documented, so it would be a blind edit. Over-volting a card that is already failing. Card 0 carries the display, so a hang there panics the Mac (memory: WindowServer watchdog). Shared cooling, so heat moves to the CPU. |
| Raise memory clock | the only lever that matches the bottleneck | GDDR5 errors are *silent wrong answers* before they are hangs. Beta 7 ticket 08 (garbage from offloaded mat-mul) already shows how hard silent errors are to find. |
| Disable power containment / CAC | removes the PowerTune clamp | Removes the card's own over-power protection in a chassis with one fan. |
| Custom fan curve (Macs Fan Control and similar) | lower temperatures, as documented [S8] | Writes SMC keys, so it is outside research-only scope. Noise. It does not raise clocks. |
| Xeon turbo | none available: the multiplier is locked | n/a |
| Log clocks/temperature/fan during existing benches | answers "does it throttle" at no extra GPU load | almost none: ioreg reads need no root. The driver samples every 1 s, so clamping inside a state cannot be seen. |
| Health check at app start | stops a failing card from producing wrong answers or hangs | The check itself dispatches to a suspect card. Keep it to one tiny command buffer with a timeout. |

## 6. What a beta 8 ticket should contain

**Ticket A (recommended): card health at app start.** Leave a card out when any of these holds:
1. **Crash history:** count `*.gpuRestart` reports whose `PCIe Device: [b:d:f]` matches the
   card, since boot or in the last 24 h. Signals beyond that: a `.panic` with an MCA whose ADDR
   decodes to the card's ECAM range. The reports are readable by this user, mode `rw-rw----
   root:_analyticsusers`. Confirm that holds for the app's user.
2. **Known-answer kernel:** on each `MTLDevice`, run tiny ADD, MUL and RMS_NORM jobs against a CPU
   reference. These are the ops that failed on 11-04 (issue 01's table). Use one command buffer,
   well under the 100 ms rule, with a wall-clock timeout. A timeout or a mismatch excludes the
   card.
3. Map each `MTLDevice.registryID` to its IORegistry PCI entry to get the bus number, so 1 and 2
   refer to the same card.

Gate: on this machine, if card 1 is still bad after issue 01's power cycle, the app plans
"card 0 + host" with no user action. If both cards pass, the app plans both. Name the
configuration that cannot run: a known-failing card cannot be emulated on a healthy machine, so
the exclusion path needs an injected fault (an environment override). Prove that override takes
effect, per CLAUDE.md rule 2.

**Ticket B (optional, small): throttle telemetry.** Extend `tools/utilcard.sh`, or the bench
harness, to record:
- `Core Clock`, `Memory Clock`, `Temperature`, `Fan Speed(%)`, `GPU Activity` per card, every 1 s;
- `pmset -g therm` (`CPU_Speed_Limit`) and `sysctl machdep.xcpm.cpu_thermal_level` /
  `gpu_thermal_level`, alongside every bench row that already runs. Do this especially for the
  hybrid CPU+GPU schedule, and for a run of at least 10 minutes.

Put the result in the method line ("clocks held at 850/1370 throughout", or the minimum seen).
Do not write a separate stress soak: the safety rules and card 1's state make that the wrong
trade. Before trusting a null result, show that the counter moves. It does: 300 at idle, 850 under
load.

**No ticket:** any clock, voltage, power-limit or fan change.

## Sources

Primary:
- [A1] Apple, Mac Pro (Late 2013) technical specifications: https://support.apple.com/112025
- [A2] Apple, Identify your Mac Pro model (MacPro6,1, newest OS Monterey): https://support.apple.com/en-us/102887
- [I1] Intel ark, Xeon E5-2697 v2: https://www.intel.com/content/www/us/en/products/sku/75283/intel-xeon-processor-e52697-v2-30m-cache-2-70-ghz/specifications.html
- [K1] Linux kernel, `drivers/gpu/drm/radeon/si_dpm.c` (power containment, CAC, DTE, TDP limit; device 0x6798): https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/radeon/si_dpm.c
- This machine (MacPro6,1, 2x D700, E5-2697 v2, macOS 15.8 24H23 via OCLP 2.5.1), read-only:
  - `ioreg -l -w0` (PerformanceStatistics, AGPM, `PP_*`, pcidebug);
  - `system_profiler SPDisplaysDataType`;
  - `sysctl -a`, `pmset -g`, `pmset -g therm`, `nvram -p`, `csrutil status`;
  - `/Library/Logs/DiagnosticReports/*.gpuRestart`, `*.panic`.

Secondary (measurements or summaries; marked UNVERIFIED in the text where used alone):
- [S1] AnandTech, The Mac Pro Review (Late 2013), pp. 9 and 14. Original offline; seen through search snippets and https://www.overclock.net/threads/anandtech-the-mac-pro-review-late-2013.1455481/
- [S2] AnandTech, PowerTune with Boost (HD 7970 GHz Ed.): https://www.anandtech.com/show/6025/radeon-hd-7970-ghz-edition-review-catching-up-to-gtx-680/2 (snippet)
- [S3] OC-Little-Translated, Polaris PowerPlay tables: https://github.com/5T33Z0/OC-Little-Translated/blob/main/11_Graphics/GPU/AMD_Radeon_Tweaks/Polaris_PowerPlay_Tables.md
- [S4] `upp` (supported families): https://pypi.org/project/upp/
- [S5] freedesktop bug 106363, PowerPlay support for SI: https://bugs.freedesktop.org/show_bug.cgi?id=106363
- [S6] Marco Arment, Turbo Boost and the New Mac Pro's CPUs: https://marco.org/2013/11/26/new-mac-pro-cpus
- [S7] iFixit, Mac Pro Late 2013 teardown: https://www.ifixit.com/Teardown/Mac+Pro+Late+2013+Teardown/20778
- [S8] Crystalidea, Optimizing thermals in Mac Pro 2013: https://crystalidea.com/blog/optimizing-thermals-in-mac-pro-2013
- [S9] Linus Tech Tips forum: https://linustechtips.com/topic/96169-anandtech-posts-mac-pro-2013-review-and-anand-loves-it/
- [S10] MacRumors, Late 2013 Mac Pro video issues repair program: https://www.macrumors.com/2016/02/06/late-2013-mac-pro-video-issues-repair-program/
- [S11] Apple Community, GPU Reset / GPU ASIC log on Mac Pro with dual D700: https://discussions.apple.com/thread/7274308; MacRumors, Mac Pro late 2013 GPU driver issues: https://forums.macrumors.com/threads/mac-pro-late-2013-gpu-driver-issues.1860297/
