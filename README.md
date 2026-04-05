# FastGIF

> The fastest, most minimal GPU-accelerated GIF creation app for iOS.  
> 2,410 lines of Swift. Zero Swift package dependencies. Every pixel through the GPU.

---

## Why?

Every GIF app on iOS forces a tradeoff:

| App | Quality | Editing | Batch | Stickers | Formats |
|-----|---------|---------|-------|----------|---------|
| **GIPHY** | Low | None | No | No | GIF only |
| **ImgPlay** | Medium | Good | No | No | GIF, MP4 |
| **Gifski** | Excellent | None | No | No | GIF only (macOS) |
| **Momento** | Medium | Basic | No | Yes | GIF only |
| **FastGIF** | **Excellent** | **Full** | **Yes** | **Yes** | **6 formats** |

Gifski has the best quality but only runs on macOS and can only convert video. ImgPlay has great editing but mediocre encoding. No iOS app combines both. **FastGIF does — in 2,410 lines of code.**

The design philosophy comes from [iA Writer](https://ia.net/writer) and [Things](https://culturedcode.com/things/): radical simplicity on the surface, progressive depth underneath. Regular users see three steps — Import, Adjust, Export. Power users discover frame-by-frame editing, custom dithering algorithms, and a `@resultBuilder` pipeline DSL.

## How It Works

### The Pipeline Kernel

Every operation in FastGIF flows through a single pipeline:

```
Source → Decode → Process → Encode → Export
```

Each stage is a Swift `Stage` protocol. Stages compose via `@resultBuilder`:

```swift
Pipeline {
    Resize(targetSize: CGSize(width: 320, height: 240))
    Quantize(colors: 128)
    Dither(.floydSteinberg, strength: 0.8)
}
```

This is the entire architecture. No coordinator pattern. No VIPER. No reactive framework. One protocol, one result builder, one `async` pipeline. The kernel is **66 lines of Swift**.

### GPU Acceleration Stack

| Framework | Purpose | Why Not Alternatives |
|-----------|---------|---------------------|
| **vImage** (Accelerate) | SIMD resize, color quantization | 100x faster than naive Swift pixel manipulation |
| **Core Image** | GPU filter chains (11 presets) | Lazy evaluation — filters compose without intermediate buffers |
| **VideoToolbox** | Hardware video decode | Decodes H.264/HEVC in silicon, not software |
| **Vision** | AI background removal | On-device person segmentation, zero model download |
| **Rust FFI** (FastGIFCore) | NeuQuant color quantization via C FFI | Gifski-quality palette optimization in a static library, no runtime dependency |

### File Structure

```
FastGIF/
├── FastGIF.xcodeproj
├── FastGIF/
│   ├── FastGIFApp.swift                          # 17 lines — app entry
│   ├── ContentView.swift                         # 53 lines — root navigation
│   ├── Kernel/
│   │   ├── Frame.swift                           # 37 lines — the atom
│   │   ├── Pipeline.swift                        # 66 lines — the kernel
│   │   ├── Decoder.swift                         # 116 lines — video/image → frames
│   │   ├── Encoder.swift                         # 246 lines — frames → 6 formats
│   │   └── ImageProcessing.swift                 # 196 lines — resize, quantize, dither, filter
│   ├── Models/
│   │   └── GIFProject.swift                      # 236 lines — @Observable document model
│   ├── Features/
│   │   ├── Import/ImportView.swift               # 112 lines — video, photos, files
│   │   ├── Editor/EditorView.swift               # 232 lines — timeline, controls, preview
│   │   ├── Editor/TrimView.swift                 # 95 lines — frame range trimming
│   │   ├── Export/ExportView.swift               # 211 lines — multi-format with size comparison
│   │   ├── Batch/BatchView.swift                 # 153 lines — folder → convert all
│   │   ├── Palette/PaletteView.swift             # 99 lines — color extraction + editing
│   │   ├── Filters/FilterView.swift              # 102 lines — 11 GPU filter presets
│   │   ├── BackgroundRemoval/
│   │   │   └── BackgroundRemoval.swift           # 52 lines — Vision AI segmentation
│   │   └── Stickers/
│   │       ├── StickerOptimizer.swift             # 80 lines — size/quality optimization
│   │       └── StickerWizardView.swift            # 163 lines — iMessage wizard
│   ├── UI/
│   │   ├── Theme.swift                           # 56 lines — iA Writer design tokens
│   │   └── Components/
│   │       └── AnimatedPreview.swift             # 88 lines — live GIF playback
│   └── RustCore/
│       ├── fastgif_core.h                        # C header for Rust FFI
│       ├── module.modulemap                       # LLVM module map
│       └── FastGIFCore.xcframework/              # Pre-built Rust static library
│           ├── ios-arm64/                         # Device slice
│           └── ios-arm64-simulator/               # Simulator slice
├── README.md
├── VISION.md
├── TECHSTACK.md
└── ROADMAP.md
```

**20 Swift files. 2,410 lines. Zero Swift package dependencies.**  
Rust crate dependencies: [`gif`](https://crates.io/crates/gif) and [`color_quant`](https://crates.io/crates/color_quant) from crates.io, compiled into a static library.

## Features

### Core
- **Frame-by-frame editor** — timeline with thumbnails, reorder, duplicate, delete, per-frame timing
- **Video → GIF** — hardware-decoded via VideoToolbox, configurable FPS extraction
- **Live animated preview** — real-time playback at natural frame timing
- **Speed curves** — 0.1x to 5.0x with live slider

### Color & Quality
- **4 dithering algorithms** — Floyd-Steinberg, Ordered, Bayer, None (with strength control)
- **Color quantization** — 16 to 256 colors, GPU-accelerated via Core Image posterize
- **Custom palette engine** — auto-extract dominant colors from any frame
- **11 GPU filter presets** — Chrome, Fade, Mono, Noir, Pixelate, Blur, Sharpen, Vignette...

### Export
- **6 formats** — GIF, APNG, WebP, MP4, MOV, HEIC sequence
- **WebP and HEIC export single-frame (static) images** — not animated; ideal for thumbnails and still exports
- **Size comparison** — see file sizes across all formats before exporting
- **iMessage Sticker Wizard** — auto-optimize to Apple's 500KB APNG limit (3 size tiers)
- **Batch processing** — drop a folder, apply presets, convert all at once

### AI
- **Background removal** — Vision framework person segmentation, per-frame, zero model download
- **Transparent sticker export** — remove background + APNG = instant iMessage stickers

## Commands

```bash
# Build
xcodebuild -project FastGIF.xcodeproj -scheme FastGIF \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -project FastGIF.xcodeproj -scheme FastGIF \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# Run (simulator)
xcodebuild -project FastGIF.xcodeproj -scheme FastGIF \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build-and-run-simulator
```

## Installation

### Prerequisites

- macOS 14+ with Xcode 16+
- iOS 18+ deployment target
- [FlowDeck CLI](https://flowdeck.studio) (recommended for build/run)

### Quick Start

```bash
# Clone
git clone git@github.com:<your-username>/fast-gif.git
cd fast-gif/FastGIF

# Option A: FlowDeck (recommended)
flowdeck init -w FastGIF.xcodeproj -s FastGIF
flowdeck build
flowdeck run

# Option B: Xcode
open FastGIF.xcodeproj
# Select FastGIF scheme → your device → Run

# Option C: Command line
xcodebuild -project FastGIF.xcodeproj -scheme FastGIF \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Physical Device

```bash
# List connected devices
flowdeck device list

# Deploy to device
flowdeck init -w FastGIF.xcodeproj -s FastGIF -D "<device-name>"
flowdeck run
```

> **Note:** Physical device is recommended for GPU pipeline testing. The simulator lacks VideoToolbox hardware acceleration and Vision framework performance differs.

## Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| State management | `@Observable` | Zero boilerplate. No Combine. No @Published. |
| Concurrency | Swift structured concurrency | Task groups for batch, cancellation propagation, no GCD |
| Pipeline composition | `@resultBuilder` DSL | Declarative, type-safe, composable in 3 lines |
| Image processing | vImage + Core Image | CPU SIMD + GPU filters. Best of both silicon paths. |
| Video decode | VideoToolbox via AVFoundation | Hardware decode in silicon. 10-50x faster than software. |
| AI features | Vision framework | On-device. No model download. No network. No privacy concerns. |
| GIF encoding | Rust FFI (FastGIFCore) | Gifski-quality NeuQuant palette optimization via C FFI. Static library, zero runtime overhead. |
| External dependencies | Zero Swift packages | Everything ships with Apple's platform SDKs, plus a pre-compiled Rust static library for encoding quality. |

## Testing Strategy

Tests live in `FastGIFTests/` and `FastGIFUITests/`. The strategy is lightweight and focused on the pipeline:

- **Unit tests** — verify each `Stage` in isolation (decode → resize → quantize → dither → encode) with known-input fixtures
- **Integration tests** — end-to-end pipeline runs: video in → GIF bytes out, assert frame count and format headers
- **UI tests** — critical user flows: import → trim → export, batch processing, sticker wizard completion
- **No mocking framework** — dependencies are protocols (`Stage`), so test doubles are just conforming structs

```bash
# Run all tests
xcodebuild test -project FastGIF.xcodeproj -scheme FastGIF \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Code Style

FastGIF follows a strict minimalism that prioritizes readability over cleverness:

- **No Combine, no RxSwift, no promises** — structured concurrency (`async`/`await`, `TaskGroup`) everywhere
- **No coordinator pattern, no VIPER** — `@Observable` models drive views directly
- **Protocol-oriented pipeline** — every operation conforms to `Stage`, composable via `@resultBuilder`
- **Explicit over implicit** — prefer `let` over `var`, prefer `enum` with associated values over dictionaries
- **One file, one responsibility** — no god objects, no 500-line view controllers

Example — the `Stage` protocol that defines the entire processing pipeline:

```swift
protocol Stage {
    func process(_ frames: [Frame]) async throws -> [Frame]
}
```

Every filter, every transform, every encode step implements this single method. Composition happens through the `@resultBuilder` DSL, not through inheritance or complex object graphs.

## Boundaries

Three-tier decision framework for changes to the codebase:

### ✅ Always
- Keep the pipeline architecture: `Stage` protocol + `@resultBuilder` composition
- Use Apple platform frameworks first (vImage, Core Image, Vision, VideoToolbox)
- Maintain the file-per-responsibility convention
- Run all existing tests before merging
- Target the 2,500-line ceiling (currently 2,410)

### ⚠️ Ask First
- Adding new Swift package dependencies — the zero-dependency constraint is intentional
- Adding new export formats — each format must justify its line-count cost
- Changing the `Frame` data structure — it's the atom everything depends on
- Modifying the Rust FFI interface (`FastGIFCore.xcframework`) — requires rebuilding the static library
- Introducing any third-party Rust crate beyond `gif` and `color_quant`

### 🚫 Never
- No Combine, no RxSwift, no reactive framework
- No coordinator pattern, no VIPER, no Clean Architecture layers
- No Core Data, no SwiftData, no local database — state is in-memory `@Observable`
- No network calls — FastGIF works entirely offline
- No analytics, no telemetry, no tracking

## License

Proprietary. All rights reserved.