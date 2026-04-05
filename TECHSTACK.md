# Tech Stack

## Why SwiftUI + Pure Apple Frameworks?

**Zero dependencies.** Every framework in FastGIF ships with iOS. No CocoaPods, no SPM packages, no version conflicts, no supply chain risk. The app compiles with `xcodebuild` and nothing else.

This is a deliberate architectural choice, not laziness:

| Concern | Our Choice | Alternatives Rejected | Why |
|---------|-----------|----------------------|-----|
| UI | SwiftUI + `@Observable` | UIKit, Combine, RxSwift | `@Observable` eliminates all reactive boilerplate. Zero wrappers. |
| Image processing | vImage (Accelerate) | GPUImage3, MetalPetal | vImage uses SIMD intrinsics — 100x faster than naive Swift. Ships with iOS. |
| GPU filters | Core Image | Metal compute shaders | CI has lazy evaluation + automatic kernel fusion. Custom Metal is v2.0. |
| Video decode | AVFoundation + VideoToolbox | FFmpeg, GStreamer | Hardware decode in silicon. No cross-compilation. No binary bloat. |
| AI segmentation | Vision framework | Core ML + custom model | On-device, zero download, Apple-optimized. Good enough for v1. |
| Concurrency | Swift structured concurrency | GCD, Combine, async-algorithms | Native cancellation, task groups for batch, no callback hell. |

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

## Future: Rust FFI for Gifski Quality

The single biggest quality improvement available is integrating the [gifski Rust crate](https://github.com/ImageOptim/gifski) (MIT licensed). Gifski uses:

- **Cross-frame palette optimization** — analyzes all frames to build a global palette, then per-frame local palettes that reference it
- **Temporal dithering** — reduces flicker between frames
- **pngquant's median-cut quantization** — superior to posterize for photographic content

Integration path:
```
Rust (gifski crate) → cargo-lipo → universal iOS static lib (.a)
                    → cbindgen → C header
                    → Swift bridging header → FastGIF Stage
```

This is planned for v1.2. The pipeline architecture makes it trivial — it's just another `Stage`.
