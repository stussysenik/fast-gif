# Roadmap

## v1.0 — The Kernel (Current)

**Status: Built & running on simulator. 2,411 LOC across 20 Swift files + 1,283 LOC tests (93 passing).**

The foundation. Every feature works through the pipeline kernel. No half-baked features — if it's listed, it compiles and runs.

- [x] Pipeline kernel with `@resultBuilder` DSL
- [x] Video → GIF (hardware-decoded via VideoToolbox)
- [x] Image sequence import (Photos picker + file import)
- [x] Frame-by-frame editor with timeline
- [x] Frame reorder, duplicate, delete
- [x] Speed control (0.1x–5.0x)
- [x] Reverse/boomerang
- [x] Color quantization (16–256 colors)
- [x] 4 dithering algorithms (Floyd-Steinberg, Ordered, Bayer, None)
- [x] 11 GPU filter presets (Core Image)
- [x] Color palette extraction
- [x] 6 export formats (GIF, APNG, WebP, MP4, MOV, HEIC)
- [x] Export size comparison across formats
- [x] AI background removal (Vision framework)
- [x] iMessage Sticker Wizard (auto-optimize to 500KB APNG)
- [x] Batch processing (folder → convert all)
- [x] iA Writer-inspired design system
- [x] `@Observable` state management (zero Combine)
- [x] Rust FFI — custom `fastgif-core` crate (NeuQuant via `color_quant` + `gif` crate), built into `FastGIFCore.xcframework`, called from `Encoder.swift`
- [x] Unit tests for pipeline stages (93 passing — resize, quantize, dither, speed, reverse, crop, filters)
- [x] Unit tests for encoding (GIF header validation, APNG signature, color fidelity roundtrip R/G/B, format dispatch)
- [ ] Integration tests (end-to-end import → edit → export)
- [ ] Performance benchmarks (frame throughput, memory ceiling)
- [ ] Physical device testing
- [ ] TestFlight build

## v1.1 — Platform Presets & Polish

**Goal: One-tap export for every platform. The "replaces 4 apps" release.**

- [ ] Platform-aware export presets:
  - [ ] Slack emoji (128×128px, under 64KB)
  - [ ] Slack message (under 2MB)
  - [ ] Discord emoji (128×128px, under 256KB)
  - [ ] Discord sticker (320×320px, under 512KB)
  - [x] iMessage sticker (300/408/618px, under 500KB)
  - [ ] Twitter/X (max 15MB, 1280px wide)
  - [ ] Instagram Stories (1080×1920px)
- [ ] Onion skinning in frame editor (semi-transparent adjacent frames)
- [ ] Per-frame delay editing (tap timing label to adjust)
- [ ] Undo/redo system
- [ ] App icon and launch screen
- [ ] App Store screenshots and metadata
- [ ] TestFlight beta

## v1.2 — Metal Shaders & System Integration

**Goal: GPU-native processing and deep OS integration.**

- [ ] Metal compute shader system:
  - [ ] Custom dithering kernels (Bayer matrix on GPU)
  - [ ] Color quantization on GPU
  - [ ] Theme-aware transitions (light/dark with shader-driven effects)
- [ ] Shortcuts integration (`AppIntents` framework)
- [ ] Share extension (convert from any app)
- [ ] Quality comparison toggle (current encoder vs. alternative quantization strategies)

## v1.3 — Creator Tools

**Goal: Professional-grade creation tools that justify premium.**

- [ ] Text overlay engine:
  - [ ] Per-frame text with animation presets (typewriter, bounce, fade, glitch)
  - [ ] Custom fonts, colors, shadows
- [ ] Draw-on-GIF (PencilKit integration for Apple Pencil)
- [ ] Speed curves (bezier timing per segment, not uniform)
- [ ] Crop with aspect ratio presets
- [ ] Trim with handles (video-style in/out points)
- [ ] Smart loop detection (AI-suggested optimal loop points)
- [ ] Shareable presets (export/import encoding settings as JSON)

## v2.0 — Community & AI

**Goal: The GIF creation platform.**

- [ ] AI text-to-GIF generation (Core ML model or API)
- [ ] AI frame interpolation (slow-mo from low FPS source)
- [ ] AI upscaling (super-resolution per frame)
- [ ] Community preset library (browse/share encoding configs)
- [ ] iPad app with multi-window support
- [ ] Mac Catalyst or native macOS app
- [ ] Widget for recent exports
- [ ] Slack App integration (create GIFs without leaving Slack)

## Principles

1. **No feature ships half-baked.** If it's in a release, it works completely. If it's not ready, it waits.
2. **The kernel is sacred.** Every feature must be expressible as a pipeline stage. No exceptions.
3. **LOC is a metric, not a goal.** We track it (2,411 app + 1,283 tests + 135 Rust) because bloat is the enemy of maintainability. But we don't sacrifice clarity for brevity.
4. **Free core, premium power.** The creation loop (import → edit → export GIF) is always free. Premium unlocks formats, batch, AI, and creator tools.
5. **Verify before shipping.** Every release is tested on physical hardware. Simulator-only testing is not sufficient for GPU work.
6. **Spec-driven development.** Every feature starts with an OpenSpec — a clear, testable description of inputs, outputs, and edge cases. Code follows the spec, not the other way around.