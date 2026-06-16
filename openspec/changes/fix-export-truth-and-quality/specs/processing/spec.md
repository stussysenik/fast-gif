# Processing — Delta

## MODIFIED Requirements

### Requirement: Resize Stage

The Resize stage SHALL scale frames to fit a maximum edge length while preserving the
source aspect ratio. It SHALL NOT force a square. Given `maxEdge`, the long edge of the
output SHALL equal `min(sourceLongEdge, maxEdge)` and the short edge SHALL be derived
from the source aspect ratio. The same Resize configuration SHALL be used by both the
preview and export pipelines (differing only in `maxEdge`).

#### Scenario: Non-square frame preserves aspect
- GIVEN a 1920×1080 source frame and `maxEdge = 480`
- WHEN the Resize stage runs
- THEN the output SHALL be 480×270 (aspect preserved), NOT 480×480

#### Scenario: Upscale is not forced
- GIVEN a source whose long edge is already below `maxEdge`
- WHEN the Resize stage runs
- THEN the frame SHALL be left at its source size

## ADDED Requirements

### Requirement: Quality Preset

The system SHALL define a `Quality` enum with exactly three cases: `draft`, `good`, and
`best`. `draft` SHALL apply nearest-color mapping with no diffusion. `good` SHALL apply
GPU 8×8 Bayer dithering. `best` SHALL apply temporal Sierra2_4a diffusion. This enum
SHALL replace the `DitherAlgorithm` enum.

#### Scenario: Preset selects the dithering strategy
- GIVEN a `Quality` value
- WHEN export runs
- THEN `draft` SHALL produce no dithering, `good` SHALL produce Bayer dithering, and
  `best` SHALL produce temporal error-diffused output

#### Scenario: Each preset is visually distinct
- GIVEN the same source frames encoded at `draft`, `good`, and `best`
- WHEN the outputs are compared
- THEN they SHALL differ in their pixel data (the preset is not a placebo)

### Requirement: Bayer Dither (GPU)

The system SHALL implement an 8×8 ordered Bayer dither as a Metal `CIColorKernel` used
by `Quality.good`. The kernel SHALL add the canonical recursive 8×8 Bayer offset,
normalized to roughly ±0.5/256, indexed by destination pixel coordinates modulo 8.

#### Scenario: Bayer offset applied on GPU
- GIVEN a frame processed at `Quality.good`
- WHEN the Bayer kernel runs
- THEN each pixel SHALL be offset by `bayer8[(y%8)*8 + (x%8)]` before quantization, and
  the operation SHALL execute on the GPU via Core Image / Metal

## REMOVED Requirements

### Requirement: Dither Stage

**Reason**: The stage ignores its `DitherAlgorithm` parameter and applies identical
`CIRandomGenerator` noise for every algorithm — a placebo — and is absent from the
preview. Replaced by the Quality Preset and Bayer Dither (GPU) requirements; real
diffusion lives in the Rust core.

### Requirement: Quantize Stage

**Reason**: `CIColorPosterize` performs per-channel level reduction, not reduction to N
palette colors, and the final palette is built by the Rust NeuQuant path anyway. The
Swift Quantize stage is removed; quantization is owned end-to-end by the Rust core so
preview and export share one quantizer.
