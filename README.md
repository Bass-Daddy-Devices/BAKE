# BAKE

**BAKE is an offline, node-based audio workstation for resampling on macOS.** Wire nodes into a patch, then bake it to a file. Nothing runs in real time, so every node can look at the whole sound, take as long as it needs, and use the GPU: whole-file analysis, look-ahead, heavy spectral work, batch processing of entire folders.

- **75 nodes:** filters, distortion and dynamics; time effects (delay, reverb, granular, beat repeat, stutter, step FX, stretch); spectral nodes (vocoder, spectral resynthesis, fractal filter, OTFT compressor); wavetables for Serum and Vital; routing; and modulation (LFOs, envelopes, followers, clocks, logic).
- **Batch processing:** run a patch over a folder, slices of a long recording, or chunks caught at each trigger; sort, split, layer, average, scatter, conform to one tempo and key; one file per input.
- **Modulate anything:** almost every sound-shaping control takes a modulation signal.
- **Custom nodes:** save a group of nodes as your own node.
- **Deterministic:** the same patch and inputs always bake the same file, bit for bit.

The documentation, including a page for every node, is in the [wiki](../../wiki).

## Requirements

- macOS 26 or later on Apple Silicon
- Xcode 27 with the Metal Toolchain (Xcode › Settings › Components)

## Build and test

```sh
# The engine, compiler and tests (Swift package)
swift test --package-path BakeCore

# The app
xcodebuild -workspace BAKE_WORKSPACE.xcworkspace -scheme BAKE -destination 'platform=macOS' \
  -derivedDataPath /tmp/bake-dd build
```

Open `BAKE_WORKSPACE.xcworkspace` (not the project) in Xcode to run the app: the workspace brings in the local `BakeCore` package. To sign it yourself, choose your own team in the BAKE target's Signing settings.

## How it's built

| Part | What it does |
|---|---|
| `BakeCore/Sources/BakeGraph` | The document model, node catalog, editing, and the graph compiler |
| `BakeCore/Sources/BakeDSP` | C++20 DSP kernels |
| `BakeCore/Sources/BakeGPU` | Metal compute kernels |
| `BakeCore/Sources/BakeRender` | The render engine: one processor per node kind |
| `BakeCore/Sources/BakeCanvas` | The SwiftUI node editor |
| `BakeCore/Sources/BakeSession` | Baking, previews, batches and file access |
| `BAKE/` | The app |

## License

BAKE is open source under the **MIT License** ([LICENSE](LICENSE)). You may use, copy, change, share and sell it, in open or closed products, as long as you keep the copyright and license notice. It comes with no warranty.

Copyright © 2026 Chris Connelly and BAKE contributors. Each contributor keeps the copyright in their own work.

- **Your work is yours.** Projects, rendered audio, wavetable exports and `.bakenode` files you make with BAKE belong to you. The license doesn't apply to them.
- **Signed builds.** Signed, ready-to-run builds of BAKE are sold by its author. Buying one supports development; building it yourself from this repository is always allowed.
- **The name.** The license covers the code, not the BAKE name or logo. If you distribute a modified version, please give it its own name and icon.
- **Earlier versions.** Code published before 2026-11-18 was released under GPLv3; those copies stay available under it. Everything from now on, including that code, is offered under MIT.
- **Third-party code** is listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Only permissively licensed dependencies are used.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first. There is no CLA: you keep your copyright, your work is released under the same MIT License as the rest of BAKE, and you sign off each commit (`git commit -s`).
