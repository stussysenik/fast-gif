# Quality Verification — Delta

## ADDED Requirements

### Requirement: Flicker Metric and Signed Baseline

The system SHALL define a deterministic flicker metric: sample the 32×32 center region
across all frames, compute per-pixel RGB variance across frames, and average. A baseline
`B₀` SHALL be measured on the unchanged (commit-1) encoder over the reference fixture and
recorded in `tests/fixtures/flicker-baseline.txt`, signed via `git hash-object` to detect
tampering.

#### Scenario: Baseline recorded and signed
- GIVEN the reference fixture and the original per-frame-palette encoder
- WHEN the baseline is measured
- THEN `B₀` SHALL be written to `flicker-baseline.txt` together with its `git hash-object`
  signature

#### Scenario: Metric is deterministic
- GIVEN the same GIF input
- WHEN the flicker metric is computed twice
- THEN it SHALL return the identical value

### Requirement: Flicker Monotonic-Decrease Gate

For each commit `N`, measured flicker SHALL satisfy `flicker(N) ≤ max(α(N)·B₀, 0.5)`,
where `α(2)=1.0`, `α(3)=0.6`, `α(4)=0.3`. The `0.5` floor guards against pathologically
small baselines.

#### Scenario: Global palette cuts flicker by ≥40%
- GIVEN the global-palette encoder (commit 3)
- WHEN flicker is measured on the fixture
- THEN it SHALL be `≤ max(0.6·B₀, 0.5)`

#### Scenario: Temporal carry achieves zero-flicker target
- GIVEN the temporal-diffusion encoder (commit 4)
- WHEN flicker is measured on the fixture
- THEN it SHALL be `≤ max(0.3·B₀, 0.5)`

### Requirement: Row-Tile Diffusion Bit-Identity (P1)

A witness test SHALL assert that tiled diffusion output is byte-identical to sequential
diffusion output for `T ∈ {1, 2, 4, 6, 8}` on a 240×240 gradient frame.

#### Scenario: Tiled equals sequential
- GIVEN a 240×240 gradient frame
- WHEN diffused sequentially and with each tile count
- THEN every tiled result SHALL be byte-for-byte equal to the sequential result

### Requirement: Preview-Export Parity (P3)

A witness test SHALL assert that the color set produced by `fastgif_preview_frame` equals
the color set produced by the export path for the same frame at `Quality.draft`.

#### Scenario: Preview color set equals export color set
- GIVEN a fixture frame, a color count, and `Quality.draft`
- WHEN both the preview FFI and the export FFI quantize it
- THEN their resulting color sets SHALL be equal

### Requirement: Sampling Sufficiency (P4)

A witness test SHALL assert that training the global palette on 8 sampled frames yields a
mean nearest-palette error no worse than training on 4 sampled frames, over the fixture.

#### Scenario: Eight samples are at least as good as four
- GIVEN the reference fixture
- WHEN palettes are trained on 8 and on 4 sampled frames
- THEN `palette_error(8) ≤ palette_error(4)`

### Requirement: Cross-Target Determinism (P5)

A witness SHALL assert that encoding the reference fixture with fixed parameters produces
byte-identical GIF output on the iOS Simulator and on an arm64 device (or two host arches
in CI).

#### Scenario: Identical bytes across hosts
- GIVEN the fixture and fixed encode parameters
- WHEN encoded on each target
- THEN the output GIF bytes SHALL be identical

### Requirement: Binary GIF Validator

The system SHALL provide a validator asserting that exported GIFs are structurally valid:
GIF89a signature, a logical screen descriptor, the expected frame count, and a
NETSCAPE2.0 loop extension when looping is requested.

#### Scenario: Valid GIF passes
- GIVEN a GIF produced by the export path with looping enabled
- WHEN the validator runs
- THEN it SHALL confirm the GIF89a header, the expected frame count, and the loop extension

#### Scenario: Truncated GIF fails
- GIVEN a truncated or malformed GIF
- WHEN the validator runs
- THEN it SHALL report the structural defect and fail
