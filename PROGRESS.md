# Progress

## Current State (2026-04-06)

**v1.0 — The Kernel: feature-complete, tested, running on simulator.**

| Metric | Value |
|--------|-------|
| App LOC | 2,411 across 20 Swift files |
| Test LOC | 1,283 across 5 test files |
| Rust LOC | 135 (fastgif-core) |
| Unit tests | 93 passing |
| E2E flows | 8 Maestro YAML flows |
| Export formats | 6 (GIF, APNG, WebP, MP4, MOV, HEIC) |
| Pipeline stages | 7 (Resize, Quantize, Dither, Filter, Crop, Reverse, Speed) |

## Session Log

### 2026-04-06 — False Color Fix & Timeline Origin

**Bugs fixed:**

1. **False color artifacts in GIF export** (`Encoder.swift:64`)
   - Root cause: `CGImageAlphaInfo.noneSkipLast` skipped writing the 4th byte per pixel. The buffer was allocated uninitialized, so Rust's NeuQuant received `[R, G, B, garbage]` per pixel. The garbage alpha corrupted neural network palette training, producing magenta/red false colors.
   - Fix: Changed to `premultipliedLast` so Core Graphics writes clean `[R, G, B, 255]`.

2. **Timeline origin mismatch** (`TrimView.swift:74`)
   - Root cause: Trim bar showed absolute video timestamps (49.7s–1:19.9s) while the frame scrubber used origin=0 (0.9s–24.4s). Different reference frames confused the user.
   - Fix: Trim label now shows relative duration (`0.0s – 30.2s`), matching the scrubber's origin.

**Tests added:**
- `testEncodeGIFPreservesRedChannel` — roundtrip red image, verify no R↔B swap
- `testEncodeGIFPreservesBlueChannel` — roundtrip blue image, verify no R↔B swap
- `testEncodeGIFRoundtripColorFidelity` — roundtrip green image, verify no false color

**Files changed:**
- `FastGIF/Kernel/Encoder.swift` — 1 line (alpha mode fix)
- `FastGIF/Features/Editor/TrimView.swift` — 2 lines (relative time label)
- `FastGIFTests/EncoderTests.swift` — 88 lines (3 color fidelity tests)

## What's Left for v1.0

- [x] Unit tests for pipeline stages (93 tests passing)
- [x] Unit tests for encoding (GIF, APNG, video — with color fidelity)
- [ ] Integration tests (end-to-end import → edit → export)
- [ ] Performance benchmarks (frame throughput, memory ceiling)
- [ ] Physical device testing
- [ ] TestFlight build
