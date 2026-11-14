# Contributing to XeonLLM

Thanks for your interest! Contributions are welcome under the project's
[GPL-3.0 license](LICENSE) — by submitting a pull request you agree that your
contribution is licensed under the same terms.

## Getting started

```bash
git clone https://github.com/SamerKharboush/xeonllm
cd xeonllm
./scripts/build-engines.sh   # one-time: builds the patched llama.cpp engines
./scripts/build-sympy.sh     # one-time: pinned CPython, SymPy, NumPy and SciPy for the math tools
./make-app.sh                # builds and packages dist/XeonLLM.app
open dist/XeonLLM.app
swift test                   # unit tests (needs full Xcode, see below)
```

Requirements: macOS 14+, Xcode Command Line Tools, CMake. No Xcode project —
the app is plain Swift Package Manager (`swift build`). **Running the unit
tests (`swift test`) additionally requires a full Xcode install**, because
XCTest ships only with Xcode, never with Command Line Tools.

> **Note on tests:** installing Xcode is not enough if your active developer
> directory still points at the Command Line Tools — `swift test` then fails
> with `no such module 'XCTest'`. Switch once with
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or scope
> it to a single command with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Project layout

| Path | Purpose |
|---|---|
| `Sources/` | SwiftUI app (one file per concern: Server, Models, Chat, Benchmark…) |
| `Assets/` | App icon source, web chat UI, donation QR |
| `patches/` | AMD Metal patches applied on top of upstream llama.cpp |
| `helpers/` | Helper processes the engine runs as tools ([SymPy](helpers/xeon-sympy/README.md), [NumPy and SciPy](helpers/xeon-scientific/README.md)) |
| `scripts/` | Reproducible engine build + DMG packaging |

## Guidelines

- **Target hardware is Intel Mac + AMD dGPU.** Test changes against a real
  Metal AMD setup when they touch the engine, server flags or memory logic.
- **English UI**: user-facing strings are plain English, and every new setting
  needs a tooltip (`.help` / `.infoTip`).
- **No new dependencies** without prior discussion — the app is intentionally
  dependency-free (SwiftPM with zero external packages).
- Keep the memory **estimator honest**: if you change `Estimator`, include the
  measurements that justify the new formula in the PR description.
- Engine changes go in `patches/` as diffs against the pinned llama.cpp commit
  (see `scripts/build-engines.sh`), never as vendored sources.


## Reporting issues

Include: macOS version, GPU model and VRAM, RAM, the model + quant you ran,
your Settings (a screenshot works), and the server log (Settings → Server log).
