# Encoding — Delta

## MODIFIED Requirements

### Requirement: Export Format Taxonomy

The system SHALL define exactly four export formats: GIF, APNG, MP4, and MOV. Each
format SHALL expose a `displayName`, `fileExtension`, `supportsTransparency` flag, and
UTI string. MP4 and MOV SHALL NOT support transparency. GIF and APNG SHALL report
`supportsTransparency` as `true`. WebP and HEIC SHALL NOT be offered, because the
current implementation cannot honestly carry an animation in those containers.

#### Scenario: Enumerating all supported formats
- GIVEN the `ExportFormat` enum
- WHEN the system enumerates all cases
- THEN exactly four formats SHALL be available: gif, apng, mp4, mov
- AND neither webp nor heic SHALL be present

#### Scenario: Transparency capability
- GIVEN any export format
- WHEN the format is GIF or APNG
- THEN `supportsTransparency` SHALL return `true`
- AND WHEN the format is MP4 or MOV, `supportsTransparency` SHALL return `false`

### Requirement: Universal Encode Interface

The system SHALL provide a single `encode(frames:format:colors:quality:loopCount:)`
function that accepts an array of `Frame` objects, an `ExportFormat`, a palette color
count, a `Quality` preset, and an optional `loopCount`. It SHALL dispatch to the correct
format-specific encoder and return the encoded data asynchronously. Every format
SHALL include ALL frames of the input array; no format may silently drop frames. The
system SHALL reject empty frame arrays with `EncoderError.noFrames`.

#### Scenario: Dispatching to GIF encoder with wired parameters
- GIVEN a non-empty frame array, `ExportFormat.gif`, a color count, and a quality preset
- WHEN `encode()` is called
- THEN the system SHALL invoke the GIF encoder, passing the caller's color count and
  quality through to the Rust FFI, and return the encoded GIF data

#### Scenario: No format drops frames
- GIVEN a non-empty frame array of N frames and any supported format
- WHEN `encode()` completes
- THEN the encoded output SHALL represent all N frames

#### Scenario: Rejecting empty frame arrays
- GIVEN an empty frame array and any format
- WHEN `encode()` is called
- THEN the system SHALL throw `EncoderError.noFrames`

### Requirement: GIF Encoding via Rust FFI

The system SHALL encode GIF files via the Rust FFI global-palette path
(`fastgif_encode_global`). The encoder SHALL convert each `CGImage` frame into an RGBA
pixel buffer using a `CGContext`. It SHALL pass the buffers with frame dimensions, delay
in centiseconds (minimum 2), the caller-provided color count (clamped to 2–256), loop
count, and a sample factor derived from the `Quality` preset. The palette color count
SHALL be the value selected in the UI, NOT a hardcoded constant. All manually allocated
pixel buffers SHALL be deallocated via `defer` regardless of success or failure.

#### Scenario: Color count is honored, not hardcoded
- GIVEN a Colors selection of 32
- WHEN the GIF encoder calls the FFI
- THEN it SHALL pass `colors = 32` (clamped to 2–256), and the resulting GIF SHALL use a
  palette of at most 32 entries

#### Scenario: Quality preset maps to sample factor
- GIVEN a `Quality` preset
- WHEN the GIF encoder calls the FFI
- THEN `draft`, `good`, and `best` SHALL map to defined sample-factor / diffusion modes
  rather than a fixed quality of 10

#### Scenario: Frame delay conversion to centiseconds
- GIVEN a Frame with a `delay` in seconds
- WHEN the GIF encoder converts the delay
- THEN it SHALL compute `delay * 100`, clamp to a minimum of 2, and pass it as `delay_cs`

#### Scenario: Pixel buffer memory deallocation
- GIVEN pixel buffers allocated during GIF encoding
- WHEN encoding completes (success or failure)
- THEN all buffers SHALL be deallocated in a `defer` block

## REMOVED Requirements

### Requirement: WebP Static Encoding

**Reason**: The implementation encodes only `frames.first`, silently dropping every
other frame of an animation. WebP is removed from the export taxonomy until animated
WebP can be done correctly (post-v1.0).

### Requirement: HEIC Static Encoding

**Reason**: Same single-frame limitation as WebP. Removed from the export taxonomy;
"export the current frame as a still" can return as an explicit, separate capability later.
