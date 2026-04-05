# Tech Stack

## Why SwiftUI + Pure Apple Frameworks?

**Zero Swift package dependencies.** Every Apple framework in FastGIF ships with iOS. No CocoaPods, no SPM packages, no version conflicts, no supply chain risk. The app compiles with `xcodebuild` and nothing else.

The one exception is a custom Rust crate (`fastgif-core`) compiled to a static library and wrapped in an XCFramework — it has its own Rust dependencies (`color_quant`, `gif`) but introduces zero Swift-level package overhead.

This is a deliberate architectural choice, not laziness:

| Concern | Our Choice | Alternatives Rejected | Why |
|---------|-----------|----------------------|-----|
| UI | SwiftUI + `@Observable` | UIKit, Combine, RxSwift | `@Observable` eliminates all reactive boilerplate. Zero wrappers. |
| Image processing | vImage (Accelerate) | GPUImage3, MetalPetal | vImage uses SIMD intrinsics — 100x faster than naive Swift. Ships with iOS. |
| GPU filters | Core Image | Metal compute shaders | CI has lazy evaluation + automatic kernel fusion. Custom Metal is v2.0. |
| Video decode | AVFoundation + VideoToolbox | FFmpeg, GStreamer | Hardware decode in silicon. No cross-compilation. No binary bloat. |
| AI segmentation | Vision framework | Core ML + custom model | On-device, zero download, Apple-optimized. Good enough for v1. |
| Concurrency | Swift structured concurrency | GCD, Combine, async-algorithms | Native cancellation, task groups for batch, no callback hell. |
| GIF encoding | Rust FFI (fastgif-core) | pure Swift LZW, gifski | NeuQuant palette optimization via color_quant. Per-frame local palettes. Compiled to static lib, zero Swift deps. |

## The Pipeline Kernel (66 Lines)

The entire architecture fits in one protocol and one result builder:

```swift
protocol Stage {
    func process(_ frames: [Frame]) async throws -> [Frame]
}

@resultBuilder
struct PipelineBuilder {
    static func buildExpression(_ stage: any Stage) -> [any Stage] { [stage] }
    static func buildBlock(_ stages: [any Stage]...) -> [any Stage] { stages.flatMap { $0 } }
    static func buildOptional(_ stage: [any Stage]?) -> [any Stage] { stage ?? [] }
    // ... buildEither, buildArray
}

struct Pipeline {
    let stages: [any Stage]
    init(@PipelineBuilder _ build: () -> [any Stage]) { stages = build() }
    
    func run(_ input: [Frame]) async throws -> [Frame] {
        var frames = input
        for stage in stages {
            try Task.checkCancellation()
            frames = try await stage.process(frames)
        }
        return frames
    }
}
```

Every feature is a `Stage`. Resize, Quantize, Dither, FilterStage, RemoveBackground, Crop, Reverse, Speed — all implement one method: `process(_ frames:) async throws -> [Frame]`.

## GPU Acceleration Deep Dive

### Layer 1: vImage (CPU SIMD)

Used for: **resize, color quantization**

vImage operates on `vImage_Buffer` — contiguous pixel arrays processed with ARM NEON SIMD instructions. A single `vImageScale_ARGB8888` call resizes a 1080p frame in ~2ms on A17 Pro. Naive Swift `CGContext` drawing takes ~50ms for the same operation.

```
Resize path: CGImage → vImage_Buffer → vImageScale_ARGB8888 → CGImage
              (decode)    (zero-copy)     (SIMD intrinsics)    (encode)
```

### Layer 2: Core Image (GPU Compute)

Used for: **filters, dithering, quantization preview**

Core Image filter graphs are lazily evaluated. Stacking 5 filters doesn't create 5 intermediate textures — the graph is fused into a single GPU kernel at render time.

```
Filter path: CGImage → CIImage → [CIFilter chain] → CIContext.createCGImage()
                        (lazy)    (lazy composition)   (single GPU dispatch)
```

### Layer 3: VideoToolbox (Hardware Decode)

Used for: **video → frames extraction**

AVFoundation's `AVAssetReaderTrackOutput` delegates to VideoToolbox for H.264/HEVC decode. This happens in dedicated silicon — not the CPU, not the GPU. The decode path:

```
Video file → AVAssetReader → VideoToolbox (silicon) → CVPixelBuffer → CIImage → CGImage
```

### Layer 4: Vision (Neural Engine)

Used for: **person/subject segmentation for background removal**

`VNGeneratePersonSegmentationRequest` runs on the Neural Engine (16-core on A17 Pro). Returns a per-pixel mask that we composite via `CIBlendWithMask`:

```
Frame → VNImageRequestHandler → Neural Engine → CVPixelBuffer mask
Frame + Mask → CIBlendWithMask → transparent background CGImage
```

## Memory Management Strategy

GIF frames are `CGImage` objects — each is a compressed pixel buffer managed by Core Graphics. Memory is proportional to frame count × dimensions:

- 100 frames at 320×240 = ~30 MB
- 100 frames at 1080×1080 = ~440 MB

Mitigation:
1. **Resize early in the pipeline** — reduce dimensions before any processing
2. **Process sequentially** — pipeline stages process one at a time, previous stage output is released
3. **Encode to disk for video** — MP4/MOV export streams to disk via AVAssetWriter, never holding all frames in memory
4. **Sticker optimizer aggressively reduces** — halves frames and colors until under 500KB

## Threading Model

```
Main Actor (UI)
    │
    ├── GIFProject (@Observable, MainActor)
    │     ├── .importVideo()  →  async on cooperative pool
    │     ├── .export()       →  async on cooperative pool
    │     └── .progress       ←  MainActor updates
    │
    └── Pipeline.run()        →  cooperative thread pool
          ├── Stage 1         →  may use vImage (CPU-bound)
          ├── Stage 2         →  may use CIContext (GPU dispatch)
          ├── Stage 3         →  may use Vision (Neural Engine)
          └── Task.checkCancellation() between each stage
```

All pipeline work runs on Swift's cooperative thread pool. UI updates flow back to MainActor via `@Observable`. Cancellation is checked between every stage — cancelling an export stops the pipeline immediately.

## Rust FFI — NeuQuant Encoding

The GIF encoder is powered by a custom Rust crate called **fastgif-core**, compiled to a static library and bridged into Swift via C FFI. This is not a future plan — it's the current production encoder.

### Rust Crate Dependencies

The crate uses two Rust libraries:

- **color_quant** — provides the NeuQuant algorithm, a neural-network-based color quantizer that produces superior palettes compared to median-cut or uniform quantization
- **gif** — handles GIF file format encoding (LZW compression, frame control extensions, looping)

### Build Pipeline

The crate is cross-compiled for iOS via `rust/build-ios.sh`, which builds two targets:

```
cargo build --release --target aarch64-apple-ios-sim    # Simulator (Apple Silicon Mac)
cargo build --release --target aarch64-apple-ios         # Physical devices
```

These are combined into a single XCFramework:

```
xcodebuild -create-xcframework \
    -library .../aarch64-apple-ios-sim/release/libfastgif_core.a -headers include/ \
    -library .../aarch64-apple-ios/release/libfastgif_core.a -headers include/ \
    -output .../RustCore/FastGIFCore.xcframework
```

### Integration Surface

| Artifact | Location |
|----------|----------|
| Rust crate source | `rust/fastgif-core/` |
| C header | `RustCore/fastgif_core.h` |
| XCFramework | `RustCore/FastGIFCore.xcframework` |
| Swift import | `import FastGIFCore` in `Encoder.swift` |

### Encoding Details

The encoder produces **per-frame local palettes** using NeuQuant — there is no global palette. Each frame gets its own optimized color table:

```swift
fastgif_encode(
    buf.baseAddress,
    buf.count,
    UInt32(min(max(colors, 2), 256)),  // colors: 2–256, clamped
    UInt16(loopCount),
    10  // quality: 1=best, 30=fastest. 10 is a good balance.
)
```

- **Colors**: 2–256 per frame, clamped to valid range
- **Quality**: NeuQuant sample factor of 10 (1 = best quality/slowest, 30 = fastest)
- **Palettes**: Local per-frame — each frame gets independently optimized colors
- **Output**: Heap-allocated `GIFOutput` struct, freed via `fastgif_free()`

The pipeline architecture makes this trivially replaceable — the Rust encoder is just another `Stage` in the pipeline. If a superior algorithm becomes available, swapping it out requires changes only in `Encoder.swift`.

## Codebase Stats

| Metric | Value |
|--------|-------|
| Swift files | 20 |
| Total Swift LOC | 2,410 |
| Rust crate | fastgif-core |
| Pipeline kernel | 66 lines |
| External Swift packages | 0 |
| Apple frameworks used | 6 (SwiftUI, AVFoundation, Accelerate, CoreImage, Vision, Photos) |