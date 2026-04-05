# Encoding Specification

## Purpose

Describes the multi-format export encoder that converts in-memory frame sequences into GIF, APNG, WebP, MP4, MOV, and HEIC outputs. The encoder provides a unified `encode()` entry point that dispatches to format-specific implementations, each with distinct capabilities and limitations regarding animation support, transparency, and encoding strategy.

## Requirements

### Requirement: Export Format Taxonomy

The system SHALL define exactly six export formats: GIF, APNG, WebP, MP4, MOV, and HEIC. Each format SHALL expose a `displayName`, `fileExtension`, `supportsTransparency` flag, and UTI string. MP4 and MOV SHALL NOT support transparency. All other formats SHALL report `supportsTransparency` as `true`.

#### Scenario: Enumerating all supported formats
- GIVEN the `ExportFormat` enum
- WHEN the system enumerates all cases
- THEN exactly six formats SHALL be available: gif, apng, webp, mp4, mov, heic

#### Scenario: Transparency capability for animated image formats
- GIVEN any export format
- WHEN the format is GIF, APNG, WebP, or HEIC
- THEN `supportsTransparency` SHALL return `true`

#### Scenario: Transparency capability for video formats
- GIVEN the MP4 or MOV export format
- WHEN `supportsTransparency` is queried
- THEN it SHALL return `false`

#### Scenario: UTI mapping per format
- GIVEN an ExportFormat
- WHEN its `uti` property is accessed
- THEN GIF SHALL return `kUTTypeGIF`, APNG SHALL return `"public.png"`, WebP SHALL return `"org.webmproject.webp"`, MP4 SHALL return `kUTTypeMPEG4`, MOV SHALL return `kUTTypeQuickTimeMovie`, and HEIC SHALL return `"public.heic"`

### Requirement: Universal Encode Interface

The system SHALL provide a single `encode(frames:format:loopCount:)` function that accepts an array of `Frame` objects, an `ExportFormat`, and an optional `loopCount`. This function SHALL dispatch to the correct format-specific encoder and return the encoded data asynchronously. The system SHALL reject empty frame arrays with `EncoderError.noFrames`.

#### Scenario: Dispatching to GIF encoder
- GIVEN a non-empty frame array and `ExportFormat.gif`
- WHEN `encode()` is called
- THEN the system SHALL invoke the GIF encoder and return the encoded GIF data

#### Scenario: Dispatching to APNG encoder
- GIVEN a non-empty frame array and `ExportFormat.apng`
- WHEN `encode()` is called
- THEN the system SHALL invoke the APNG encoder and return the encoded APNG data

#### Scenario: Dispatching to video encoder
- GIVEN a non-empty frame array and `ExportFormat.mp4` or `ExportFormat.mov`
- WHEN `encode()` is called
- THEN the system SHALL write to a temporary file using AVAssetWriter, read the file contents back as `Data`, and delete the temporary file

#### Scenario: Dispatching to static-only encoder
- GIVEN a non-empty frame array and `ExportFormat.webp` or `ExportFormat.heic`
- WHEN `encode()` is called
- THEN the system SHALL encode only the first frame and return the single-frame data

#### Scenario: Rejecting empty frame arrays
- GIVEN an empty frame array and any format
- WHEN `encode()` is called
- THEN the system SHALL throw `EncoderError.noFrames`

### Requirement: GIF Encoding via Rust FFI

The system SHALL encode GIF files using the Rust FFI `fastgif_encode()` function. The encoder SHALL convert each `CGImage` frame into an RGBA pixel buffer using a `CGContext` with `noneSkipLast` alpha info. The system SHALL pass the pixel buffers along with frame dimensions, delay in centiseconds (minimum 2), color count (clamped to 2–256), loop count, and a fixed quality value of 10. All manually allocated pixel buffers SHALL be deallocated after encoding completes, regardless of success or failure.

#### Scenario: Converting frames to RGBA pixel buffers
- GIVEN a Frame with a CGImage
- WHEN the GIF encoder processes the frame
- THEN it SHALL allocate an RGBA pixel buffer of size `width * height * 4`, create a CGContext with `noneSkipLast` alpha, draw the CGImage into the context, and pass the buffer pointer to the Rust FFI

#### Scenario: Frame delay conversion to centiseconds
- GIVEN a Frame with a `delay` in seconds
- WHEN the GIF encoder converts the delay
- THEN it SHALL compute `delay * 100` as centiseconds, clamp the result to a minimum of 2, and pass it as `delay_cs` to the Rust FFI

#### Scenario: Color count clamping
- GIVEN a requested color count value
- WHEN the GIF encoder passes it to the Rust FFI
- THEN it SHALL clamp the value to the range 2–256 inclusive using `min(max(colors, 2), 256)`

#### Scenario: Quality parameter
- GIVEN any GIF encoding operation
- WHEN the encoder calls `fastgif_encode()`
- THEN the quality parameter SHALL be fixed at 10

#### Scenario: Pixel buffer memory deallocation
- GIVEN pixel buffers allocated during GIF encoding
- WHEN the encoding operation completes (success or failure)
- THEN all pixel buffers SHALL be deallocated via a `defer` block that iterates and deallocates each buffer

#### Scenario: Handling Rust FFI encoding failure
- GIVEN valid frame data passed to `fastgif_encode()`
- WHEN the function returns `NULL`
- THEN the system SHALL throw `EncoderError.finalizeFailed`

#### Scenario: Extracting encoded data from FFI result
- GIVEN a non-null `GIFOutput` pointer from `fastgif_encode()`
- WHEN the encoder reads the result
- THEN it SHALL create `Data` from `result.pointee.data` with `result.pointee.len` bytes, and schedule `fastgif_free()` via a `defer` block

### Requirement: APNG Encoding

The system SHALL encode APNG files using `CGImageDestination` with the `"public.png"` UTI. The encoder SHALL set the `kCGImagePropertyAPNGLoopCount` property on the destination and the `kCGImagePropertyAPNGDelayTime` property on each frame. All frames in the input array SHALL be included in the output.

#### Scenario: Creating APNG destination
- GIVEN a non-empty frame array
- WHEN APNG encoding begins
- THEN the system SHALL create a `CGImageDestination` with `"public.png"` UTI and frame count equal to the input array size

#### Scenario: Setting loop count
- GIVEN a loop count value
- WHEN the encoder configures the APNG destination
- THEN it SHALL set `kCGImagePropertyAPNGLoopCount` in the top-level PNG dictionary via `CGImageDestinationSetProperties()`

#### Scenario: Encoding each frame with delay
- GIVEN a Frame with a CGImage and delay value
- WHEN the frame is added to the APNG destination
- THEN the system SHALL add the image with a frame property dictionary containing `kCGImagePropertyAPNGDelayTime` set to the frame's delay in seconds

#### Scenario: APNG creation failure
- GIVEN a frame array
- WHEN `CGImageDestinationCreateWithData()` returns nil
- THEN the system SHALL throw `EncoderError.creationFailed`

#### Scenario: APNG finalization failure
- GIVEN all frames have been added
- WHEN `CGImageDestinationFinalize()` returns false
- THEN the system SHALL throw `EncoderError.finalizeFailed`

### Requirement: MP4 and MOV Video Encoding

The system SHALL encode MP4 and MOV files using `AVAssetWriter` with H.264 codec. The encoder SHALL use `AVAssetWriterInputPixelBufferAdaptor` with BGRA pixel buffers rendered via `CIContext`. Frame timing SHALL be managed with `CMTime` at a preferred timescale of 600. The system SHALL write to a temporary file at the provided output URL and the caller is responsible for file cleanup.

#### Scenario: Configuring H.264 output
- GIVEN a Frame array and an ExportFormat of MP4 or MOV
- WHEN the video encoder creates an AVAssetWriter
- THEN it SHALL use `AVVideoCodecType.h264`, set width and height from the first frame's size, and use `.mp4` or `.mov` file type accordingly

#### Scenario: Pixel buffer adaptor configuration
- GIVEN the video encoding setup
- WHEN the adaptor is created
- THEN it SHALL request `kCVPixelFormatType_32BGRA` pixel buffers with dimensions matching the first frame

#### Scenario: Rendering frames to pixel buffers
- GIVEN a Frame with a CGImage
- WHEN the encoder processes the frame
- THEN it SHALL create a `CIImage` from the CGImage, obtain a pixel buffer from the adaptor's buffer pool, render the CIImage to the pixel buffer using `CIContext`, and append it to the adaptor at the current presentation time

#### Scenario: Frame timing progression
- GIVEN frames with individual delay values
- WHEN the encoder writes frames sequentially
- THEN each frame's presentation time SHALL be the cumulative sum of all preceding frame delays, starting at zero, using `CMTime` with preferredTimescale 600

#### Scenario: Handling backpressure
- GIVEN the AVAssetWriterInput is not ready for more data
- WHEN the encoder attempts to append a frame
- THEN it SHALL sleep for 10 milliseconds and retry until the input reports readiness

#### Scenario: Task cancellation support
- GIVEN an in-progress video encoding operation
- WHEN `Task.checkCancellation()` detects cancellation
- THEN the system SHALL throw a cancellation error and stop encoding

#### Scenario: Buffer pool failure
- GIVEN the pixel buffer adaptor
- WHEN `adaptor.pixelBufferPool` is nil
- THEN the system SHALL throw `EncoderError.bufferPoolFailed`

#### Scenario: Pixel buffer creation failure
- GIVEN a valid pixel buffer pool
- WHEN `CVPixelBufferPoolCreatePixelBuffer()` fails to produce a buffer
- THEN the system SHALL throw `EncoderError.bufferCreationFailed`

#### Scenario: Writer failure after finishing
- GIVEN all frames have been appended and `finishWriting()` completes
- WHEN `writer.status` is `.failed`
- THEN the system SHALL throw the writer's error, or `EncoderError.finalizeFailed` if no error is available

### Requirement: WebP Static Encoding

The system SHALL encode WebP files as single-frame images using `CGImageDestination` with the `"org.webmproject.webp"` UTI. Only the first frame of the input array SHALL be encoded. The system SHALL NOT produce animated WebP output.

#### Scenario: Encoding a single WebP frame
- GIVEN a non-empty frame array and `ExportFormat.webp`
- WHEN the encoder runs
- THEN it SHALL create a `CGImageDestination` with `"org.webmproject.webp"` UTI and frame count of 1, add `frames.first.image` with no properties, and finalize

#### Scenario: WebP destination creation failure
- GIVEN a frame array
- WHEN `CGImageDestinationCreateWithData()` returns nil for WebP
- THEN the system SHALL throw `EncoderError.formatUnsupported`

#### Scenario: WebP finalization failure
- GIVEN a single frame has been added
- WHEN `CGImageDestinationFinalize()` returns false
- THEN the system SHALL throw `EncoderError.finalizeFailed`

### Requirement: HEIC Static Encoding

The system SHALL encode HEIC files as single-frame images using `CGImageDestination` with the `"public.heic"` UTI. Only the first frame of the input array SHALL be encoded. The system SHALL NOT produce animated HEIC output.

#### Scenario: Encoding a single HEIC frame
- GIVEN a non-empty frame array and `ExportFormat.heic`
- WHEN the encoder runs
- THEN it SHALL create a `CGImageDestination` with `"public.heic"` UTI and frame count of 1, add `frames.first.image` with no properties, and finalize

#### Scenario: HEIC destination creation failure
- GIVEN a frame array
- WHEN `CGImageDestinationCreateWithData()` returns nil for HEIC
- THEN the system SHALL throw `EncoderError.formatUnsupported`

#### Scenario: HEIC finalization failure
- GIVEN a single frame has been added
- WHEN `CGImageDestinationFinalize()` returns false
- THEN the system SHALL throw `EncoderError.finalizeFailed`

### Requirement: Encoder Error Taxonomy

The system SHALL define an `EncoderError` enum conforming to `Error` and `LocalizedError` with exactly six cases: `creationFailed`, `finalizeFailed`, `noFrames`, `bufferPoolFailed`, `bufferCreationFailed`, and `formatUnsupported`. Each case SHALL provide a human-readable `errorDescription`.

#### Scenario: Error descriptions
- GIVEN each EncoderError case
- WHEN `errorDescription` is accessed
- THEN `creationFailed` SHALL return "Couldn't create encoder", `finalizeFailed` SHALL return "Encoding failed", `noFrames` SHALL return "No frames to encode", `bufferPoolFailed` SHALL return "Pixel buffer pool unavailable", `bufferCreationFailed` SHALL return "Couldn't create pixel buffer", and `formatUnsupported` SHALL return "Format not supported on this device"

### Requirement: Temporary File Management for Video Formats

When encoding MP4 or MOV, the system SHALL write output to a temporary file in the system temporary directory with a UUID-based filename and appropriate file extension. After reading the file contents into `Data`, the system SHALL delete the temporary file.

#### Scenario: Temporary file creation and cleanup
- GIVEN an MP4 or MOV encoding request
- WHEN `encode()` dispatches to the video encoder
- THEN it SHALL create a URL at `FileManager.default.temporaryDirectory` with a UUID filename and the format's file extension, pass it to the video encoder, read the resulting file as `Data`, and delete the file via a `defer` block

### Requirement: Memory Management for GIF Pixel Buffers

The system SHALL manually allocate and deallocate RGBA pixel buffers during GIF encoding. All buffers allocated for frame conversion SHALL be tracked in an array and deallocated in a `defer` block, ensuring cleanup regardless of whether encoding succeeds or throws.

#### Scenario: Cleanup on successful encoding
- GIVEN pixel buffers allocated for GIF encoding
- WHEN `fastgif_encode()` returns a valid result
- THEN all pixel buffers SHALL be deallocated before the function returns

#### Scenario: Cleanup on encoding failure
- GIVEN pixel buffers allocated for GIF encoding
- WHEN `fastgif_encode()` returns NULL
- THEN all pixel buffers SHALL be deallocated before the error propagates

#### Scenario: Cleanup on CGContext creation failure
- GIVEN a frame where CGContext creation fails
- WHEN the buffer for that frame cannot be used
- THEN the individual buffer SHALL be deallocated immediately, and remaining buffers SHALL still be deallocated in the `defer` block