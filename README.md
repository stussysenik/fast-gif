# FastGIF

> The fastest, most minimal GPU-accelerated GIF creation app for iOS.  
> 1,992 lines of Swift. Zero dependencies. Every pixel through the GPU.

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

Gifski has the best quality but only runs on macOS and can only convert video. ImgPlay has great editing but mediocre encoding. No iOS app combines both. **FastGIF does — in under 2,000 lines of code.**

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

### File Structure

```
FastGIF/
├── FastGIF.xcodeproj
├── FastGIF/
│   ├── FastGIFApp.swift              # 17 lines — app entry
│   ├── ContentView.swift             # 53 lines — root navigation
│   ├── Kernel/
│   │   ├── Frame.swift               # 37 lines — the atom
│   │   ├── Pipeline.swift            # 66 lines — the kernel
│   │   ├── Decoder.swift             # 95 lines — video/image → frames
│   │   ├── Encoder.swift             # 205 lines — frames → 6 formats
│   │   └── ImageProcessing.swift     # 181 lines — resize, quantize, dither, filter
│   ├── Models/
│   │   └── GIFProject.swift          # 128 lines — @Observable document model
│   ├── Features/
│   │   ├── Import/ImportView.swift            # video, photos, files
│   │   ├── Editor/EditorView.swift            # timeline, controls, preview
│   │   ├── Export/ExportView.swift            # multi-format with size comparison
│   │   ├── Batch/BatchView.swift              # folder → convert all
│   │   ├── Palette/PaletteView.swift          # color extraction + editing
│   │   ├── Filters/FilterView.swift           # 11 GPU filter presets
│   │   ├── BackgroundRemoval/                 # Vision AI segmentation
│   │   └── Stickers/                          # iMessage wizard + optimizer
│   └── UI/
│       ├── Theme.swift               # iA Writer design tokens
│       └── Components/               # AnimatedPreview, ProcessingOverlay
├── README.md
├── VISION.md
├── TECHSTACK.md
└── ROADMAP.md
```

**19 Swift files. 1,992 lines. Zero external dependencies.**

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
- **Size comparison** — see file sizes across all formats before exporting
- **iMessage Sticker Wizard** — auto-optimize to Apple's 500KB APNG limit (3 size tiers)
- **Batch processing** — drop a folder, apply presets, convert all at once

### AI
- **Background removal** — Vision framework person segmentation, per-frame, zero model download
- **Transparent sticker export** — remove background + APNG = instant iMessage stickers

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
| External dependencies | Zero | Everything ships with Apple's platform SDKs. |

## License

Proprietary. All rights reserved.
