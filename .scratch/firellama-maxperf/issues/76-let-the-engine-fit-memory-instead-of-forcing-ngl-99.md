# 76: let the engine fit memory instead of forcing `-ngl 99`

Status: open (needs-triage)
Type: research
Blocked by: none. 75 is not required: the two tickets decide different things and either can
land first (see Relation to 75).

## Problem

The app always passes `-ngl` (`Sources/Servers/Server.swift:359`), and the default is 99
(`Sources/Settings/SettingsTab.swift:30`). The engine's own fit then refuses to run:

    n_gpu_layers already set by user to 99, abort

`vendor/llama.cpp/common/fit.cpp:463-465`. The engine logs that as a warning and continues with
the parameters as given (`vendor/llama.cpp/common/fit.cpp:895`); the app already shows it as a
note (`Sources/Servers/Server.swift:2659-2669`, field at `Sources/Servers/Server.swift:1834-1842`).

So the one sizing pass that reads free device memory per card never runs, and the placement and
the context size are whatever the app guessed. That is the 14B-at-32k overcommit in ticket 75:
9 GB of weights plus a 32k f16 KV on two 6.44 GB cards.

## What the engine already has

The fit is on by default, is called before the model loads
(`vendor/llama.cpp/common/common.cpp:1274`, call at `:1299-1305`). It takes four options:

| option | file:line | default | meaning |
|---|---|---|---|
| `-fit`, `--fit` | `vendor/llama.cpp/common/arg.cpp:2891` | on (`vendor/llama.cpp/common/common.h:485`) | adjust unset arguments to fit device memory |
| `-fitt`, `--fit-target` | `vendor/llama.cpp/common/arg.cpp:2935` | 1024 MiB per device (`vendor/llama.cpp/common/common.h:491`) | target free memory left on each device, comma list |
| `-fitc`, `--fit-ctx` | `vendor/llama.cpp/common/arg.cpp:2960` | 4096 (`vendor/llama.cpp/common/common.h:488`) | smallest context the fit may reduce to |
| `-fitp`, `--fit-print` | `vendor/llama.cpp/common/arg.cpp:2921` | off (`vendor/llama.cpp/common/common.h:487`) | print the estimated requirement |

## Open questions

### 1. What "free memory" does the fit read on a D700?

Read from source, not measured. The fit calls `ggml_backend_dev_memory` per device
(`vendor/llama.cpp/common/fit.cpp:111-133`). The Metal implementation is
`vendor/llama.cpp/ggml/src/ggml-metal/ggml-metal-device.m:2561-2570`:

    *total     = dev->mtl_device.recommendedMaxWorkingSetSize;
    size_t cur = dev->mtl_device.currentAllocatedSize;
    *free      = *total > cur ? *total - cur : 0;

So on this box the fit reads `recommendedMaxWorkingSetSize` (6144 MiB per card, logged at
`vendor/llama.cpp/ggml/src/ggml-metal/ggml-metal-device.m:2274`) minus what this process has
already allocated, not a larger number. It is the same ceiling the app's rule uses. What
`currentAllocatedSize` is at that moment still needs a run.

### 2. Does it shrink context before moving layers to the CPU?

From source: yes, in that order, but only when the context size was left unset. Step 2 reduces
context (`vendor/llama.cpp/common/fit.cpp:373-457`) and step 3 fills dense layers back to front
(`vendor/llama.cpp/common/fit.cpp:488`, loop at `:675`). The context path runs only when
`params.n_ctx == 0` (`vendor/llama.cpp/common/fit.cpp:198`, `:393`); a context size set by the
user logs `context size set by user to ... -> no change`
(`vendor/llama.cpp/common/fit.cpp:455`).

The app passes `-c 32768` (`Sources/Servers/Server.swift:360`), so a launch that only dropped
`-ngl` would not shrink the context; it would move layer fractions to the CPU. That is the slow
path on this hardware: the 35B Q6_K partly on one D700 decodes at 0.1450 tok/s against
11.1015 tok/s with everything on the host (ticket 67, lines 14 and 16; the 76x is line 23), and
ticket 67's rule is that a partial offload of a dense model is the case to avoid. Dropping `-c`
is what lets `-fitc` (default 4096) decide. Passing `-c 0` also forbids reduction: the argument
handler sets `fit_params_min_ctx = UINT32_MAX` for it
(`vendor/llama.cpp/common/arg.cpp:1666-1668`).

### 3. Does it compose with `--split-mode tensor`?

Partly, from source. With more than one device the fit refuses `LLAMA_SPLIT_MODE_ROW`
(`vendor/llama.cpp/common/fit.cpp:477`) and any user-set `tensor_split`
(`vendor/llama.cpp/common/fit.cpp:470-474`), and it writes per-device layer counts. `tensor`
(`LLAMA_SPLIT_MODE_TENSOR`, `vendor/llama.cpp/include/llama.h:206`) is not rejected in that
list, but "fill dense layers back to front" is a layer-split shape, so what it does under a
tensor split is untested. The app passes `-ts` only when `ncmoe > 0`
(`Sources/Servers/Server.swift:402`, `:246`), so a plain tensor split sends no `-ts`.

### 4. Extra: it cannot run beside the app's auto plan

`--dynamic-moe` is passed under the auto plan (`Sources/Servers/Server.swift:371`). The plan sets
`params.fit_params = false` and `params.n_gpu_layers = 999`
(`vendor/llama.cpp/common/tosh-plan.cpp:1294-1295`) and, in the expert modes, writes
`tensor_buft_overrides` (`vendor/llama.cpp/common/tosh-plan.cpp:1306-1307`, helper at `:621-632`),
which the fit also rejects
(`vendor/llama.cpp/common/fit.cpp:484-486`). The two are alternatives, not layers.

## Experiments (not run)

Each needs a free pair of cards; the release gate is using both. Use a scratch port, never 8080.
Binary: the shipped engine, `dist/XeonLLM.app/Contents/Resources/bin/llama-server`. Model:
`<Qwen3-14B-Q4_K_M.gguf>`. No `-ngl` in any run: it makes the fit abort
(`vendor/llama.cpp/common/fit.cpp:464`).

E1, what free memory is read:

    GGML_METAL_DEVICE_LIST=0,1 dist/XeonLLM.app/Contents/Resources/bin/llama-server \
      -m <Qwen3-14B-Q4_K_M.gguf> --fit on --fit-print on -lv 4 \
      -fa 1 --host 127.0.0.1 --port 8391

Read the per-device `total` and `free` in the print, and compare with the
`recommendedMaxWorkingSetSize` line the Metal backend logs at init.

E2, context before layers. Two runs, same flags as E1 plus:

    -fitc 4096                      # if there is a deficit: "context size reduced from ... to ..."
    -c 32768                        # control: expect "context size set by user ... -> no change"
                                    # and "filling dense layers back-to-front"

Grep the `-lv 4` log for `context size` and `ngl_per_device`. If neither string appears, `-lv 4`
is not reaching the fit and the run proves nothing.

E3, tensor split. Same model, `-fitc 4096`, once per split mode:

    --split-mode layer     # control
    --split-mode tensor
    --split-mode row       # expect abort at fit.cpp:477
    --split-mode layer -ts 1,1   # expect abort at fit.cpp:470-474

Record for each: whether the server comes up, the per-device layer counts, and the memory
breakdown table at shutdown (`vendor/llama.cpp/common/fit.cpp:922-926`, printed by
`vendor/llama.cpp/tools/server/server.cpp:931`).

## Relation to 75

75 is the app's rule (`Sources/Hardware/Hardware.swift:470-485`) and decides host versus card
before the launch, from the model's size and the hardware. 76 would let the engine pick context
size and offload inside the card path. 75 can land alone and its per-card arithmetic is still
needed for the host-versus-card call whatever the engine does. If 76 works, the app can stop
guessing context size and offload on the card path, and 75's warning becomes the fallback for
runs where the fit gives up.

## Comments
