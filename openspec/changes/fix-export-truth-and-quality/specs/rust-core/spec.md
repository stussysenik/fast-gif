# Rust Core — Delta

## MODIFIED Requirements

### Requirement: Crate Identity and Dependencies

The library SHALL be named `fastgif-core` and published as a static library
(`staticlib`). It SHALL depend on `color_quant` 1.1 and `gif` 0.13, and SHALL add
`rayon` 1.10 and `crossbeam-utils` 0.8 for parallel row-tile diffusion. The release
profile SHALL set `opt-level=3`, `lto=true`, `codegen-units=1`, `strip=true`.

#### Scenario: Dependency set
- GIVEN the crate's dependency declarations
- WHEN the build resolves dependencies
- THEN `color_quant` 1.1, `gif` 0.13, `rayon` 1.10, and `crossbeam-utils` 0.8 SHALL be present

#### Scenario: Crate type configuration
- GIVEN `Cargo.toml`
- WHEN the crate is built
- THEN `crate-type` SHALL be `["staticlib"]`

### Requirement: C Header Interface

The library SHALL expose a C header (`fastgif_core.h`) defining the `RawFrame` and
`GIFOutput` structs and the functions `fastgif_encode`, `fastgif_encode_global`,
`fastgif_preview_frame`, `fastgif_free`, and `fastgif_raw_frame_free`, all with C
linkage guarded by `extern "C"`.

#### Scenario: Exported function set
- GIVEN the header
- WHEN the host application links against the library
- THEN it SHALL be able to call `fastgif_encode_global`, `fastgif_preview_frame`, and
  `fastgif_raw_frame_free` in addition to `fastgif_encode` and `fastgif_free`

#### Scenario: Struct layout unchanged
- GIVEN the header
- WHEN a host defines a `RawFrame`
- THEN it SHALL contain `rgba` (const uint8_t*), `width` (uint32_t), `height` (uint32_t),
  and `delay_cs` (uint16_t)

## ADDED Requirements

### Requirement: Global Palette Optimization

The system SHALL provide `fastgif_encode_global()` which trains a single `NeuQuant`
palette on a fixed sample of frames (8 evenly-spaced frames, or all frames when fewer
than 8) and applies that one palette to every frame. The GIF encoder SHALL be
initialized WITH this global palette; per-frame local palettes SHALL NOT be used on
this path.

#### Scenario: Single palette trained on a sample
- GIVEN N input frames
- WHEN `fastgif_encode_global()` runs
- THEN it SHALL sample `min(8, N)` evenly-spaced frames, train one `NeuQuant` on their
  combined pixels, and use the resulting palette as the GIF global palette for all N frames

#### Scenario: Flat region is stable across frames
- GIVEN a region whose input pixels are byte-identical across all frames
- WHEN encoded via `fastgif_encode_global()` at `Quality.draft`
- THEN that region SHALL map to a single palette index in every output frame

### Requirement: Temporal Error Diffusion

The system SHALL provide Sierra2_4a error diffusion. On the spatial path
(`diffuse_sequential`) error SHALL diffuse in raster order, zero-seeded per frame. On
the temporal path the residual error buffer SHALL carry from frame `n-1` to frame `n`.
A scene cut (>20% of pixels changing beyond a threshold between consecutive frames)
SHALL reset the carried error to zero.

#### Scenario: Temporal carry across frames
- GIVEN consecutive frames with no scene cut
- WHEN diffusion runs on frame `n`
- THEN it SHALL initialize its error buffer from frame `n-1`'s residual error

#### Scenario: Scene-cut reset
- GIVEN consecutive frames where more than 20% of pixels change beyond threshold
- WHEN diffusion runs on the later frame
- THEN the carried error SHALL be reset to zero before diffusing

### Requirement: Preview Frame FFI

The system SHALL provide `fastgif_preview_frame()` which quantizes a single frame using
the same `NeuQuant` + nearest-index path as export, returning the quantized RGBA for
display. Buffers returned by it SHALL be freed via `fastgif_raw_frame_free()`.

#### Scenario: Preview uses the export quantizer
- GIVEN one frame, a color count, and `Quality.draft`
- WHEN `fastgif_preview_frame()` runs
- THEN it SHALL produce the same color set as `fastgif_encode_global()` would for that
  frame at the same color count and quality

### Requirement: Deterministic Fixed-Point Quantization

Error-diffusion accumulation SHALL use fixed-point integer arithmetic so that output is
byte-identical regardless of host architecture (simulator vs device).

#### Scenario: Cross-target byte identity
- GIVEN the reference fixture and fixed encode parameters
- WHEN encoded on the iOS Simulator and on an arm64 device
- THEN the produced GIF bytes SHALL be identical

### Requirement: Row-Tile Parallel Diffusion

The system SHALL provide `diffuse_tiled()` which partitions a frame into `T` horizontal
tiles processed in parallel (rayon), where tile `t` may only advance once tile `t-1` has
cleared Sierra's 2-row footprint. Its output SHALL be byte-identical to
`diffuse_sequential()` for any `T`.

#### Scenario: Tiled equals sequential
- GIVEN a 240×240 gradient frame
- WHEN diffused with `T ∈ {1, 2, 4, 6, 8}`
- THEN every tiled result SHALL be byte-identical to the sequential result

### Requirement: Encode Cancellation and Progress

`fastgif_encode_global()` SHALL accept a cancellation flag (checked between frames) and
an optional progress callback. When cancellation is observed it SHALL stop, free any
partial allocation, and return `NULL`.

#### Scenario: Cancellation mid-encode
- GIVEN an in-progress multi-frame encode
- WHEN the cancellation flag is set between frames
- THEN the function SHALL stop, free partial buffers, and return `NULL`

## REMOVED Requirements

### Requirement: NeuQuant Per-Frame Palette Optimization

**Reason**: Per-frame local palettes are the root cause of inter-frame flicker
(measured: a constant input pixel exported as 5 distinct colors over 8 frames). Replaced
by the Global Palette Optimization + Temporal Error Diffusion requirements. The legacy
`fastgif_encode()` may remain for compatibility but is no longer the GIF export path.
