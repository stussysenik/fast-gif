# Image Processing Specification

## Purpose

Defines the contract for each image processing stage in the FastGIF pipeline. Every stage conforms to the `Stage` protocol and transforms an array of `Frame` values asynchronously. Processing stages are GPU-accelerated where possible, gracefully fall back on failure, and yield cooperatively to avoid blocking the system.

## Requirements

### Requirement: Resize Stage

The `Resize` stage SHALL scale every frame to a target size using the Accelerate framework's vImage SIMD primitives. It MUST use `vImageScale_ARGB8888` with the `kvImageHighQualityResampling` flag. The stage SHALL yield between frames via `Task.yield()` to maintain cooperative concurrency. Each resized frame MUST preserve the original frame's `delay` value. If any individual frame fails to resize, the stage SHALL throw `ProcessingError.resizeFailed`.

#### Scenario: Successful resize to target dimensions
- GIVEN a set of frames with varying dimensions
- WHEN Resize is initialized with targetSize CGSize(width: 320, height: 240) and processes the frames
- THEN every output frame SHALL have a width of 320 and height of 240
- AND each output frame SHALL retain its original delay value

#### Scenario: Resize preserves frame delay
- GIVEN a frame with delay 0.05 seconds
- WHEN Resize processes the frame
- THEN the output frame SHALL have delay 0.05 seconds

#### Scenario: Resize failure throws ProcessingError
- GIVEN a frame whose CGImage has an unsupported color space
- WHEN Resize attempts to create a vImage_CGImageFormat
- THEN the stage SHALL throw ProcessingError.resizeFailed

#### Scenario: Resize yields between frames
- GIVEN 100 frames to resize
- WHEN Resize processes each frame
- THEN the stage SHALL call `await Task.yield()` after appending each result frame

#### Scenario: Resize uses high-quality resampling
- GIVEN any valid input frame
- WHEN Resize performs scaling
- THEN it MUST use kvImageHighQualityResampling as the vImage flag

#### Scenario: Resize handles nil color space gracefully
- GIVEN a CGImage with a nil color space
- WHEN Resize attempts to build the vImage format
- THEN it SHALL fall back to sRGB as the color space

### Requirement: Quantize Stage

The `Quantize` stage SHALL reduce the color palette of each frame using Core Image's `CIColorPosterize` filter. The `colors` parameter MUST be clamped to the range 2–256 inclusive. The posterize level SHALL be computed as `max(2, Int(log2(colors)))`. If Core Image filter creation or rendering fails for a given frame, the stage SHALL return the original frame unchanged (fallback behavior). The stage MUST use a GPU-accelerated `CIContext` with `useSoftwareRenderer: false`.

#### Scenario: Colors clamped to minimum of 2
- GIVEN Quantize initialized with colors: 1
- WHEN the init clamps the value
- THEN the internal colors SHALL be 2

#### Scenario: Colors clamped to maximum of 256
- GIVEN Quantize initialized with colors: 512
- WHEN the init clamps the value
- THEN the internal colors SHALL be 256

#### Scenario: Posterize levels computed from colors
- GIVEN Quantize initialized with colors: 256
- WHEN the stage processes frames
- THEN it SHALL set CIColorPosterize inputLevels to max(2, Int(log2(256))) which is 8

#### Scenario: Posterize levels for low color count
- GIVEN Quantize initialized with colors: 4
- WHEN the stage processes frames
- THEN it SHALL set inputLevels to max(2, Int(log2(4))) which is 2

#### Scenario: Quantize falls back on filter failure
- GIVEN a frame that causes CIFilter creation to return nil
- WHEN Quantize processes that frame
- THEN the output SHALL be the original frame unchanged

#### Scenario: Quantize falls back on render failure
- GIVEN a frame where CIContext.createCGImage returns nil
- WHEN Quantize processes that frame
- THEN the output SHALL be the original frame unchanged

#### Scenario: Quantize preserves frame delay
- GIVEN a frame with delay 0.1 seconds
- WHEN Quantize processes the frame
- THEN the output frame SHALL have delay 0.1 seconds

### Requirement: Dither Stage

The `Dither` stage SHALL apply noise-based dithering to frames using Core Image. It SHALL support four algorithms: `floydSteinberg`, `ordered`, `bayer`, and `none`. When the algorithm is `none`, the stage MUST pass all frames through unchanged without any processing. For all other algorithms, the stage SHALL generate random noise via `CIRandomGenerator`, scale the noise by the strength parameter using `CIColorMatrix` (per-channel multiplier of `strength * 0.05`), crop the noise to match the source image extent, and composite the noise onto the source using `CIAdditionCompositing`. The default strength SHALL be 1.0. If noise generation or compositing fails, the stage SHALL return the original frame.

#### Scenario: None algorithm passes through
- GIVEN Dither initialized with algorithm: .none
- WHEN the stage processes any set of frames
- THEN the output frames SHALL be identical to the input frames (same objects)

#### Scenario: Floyd-Steinberg applies noise compositing
- GIVEN Dither initialized with algorithm: .floydSteinberg and strength: 1.0
- WHEN the stage processes a frame
- THEN it SHALL apply CIRandomGenerator, CIColorMatrix, and CIAdditionCompositing to produce the output

#### Scenario: Noise scaled by strength parameter
- GIVEN Dither initialized with strength: 2.0
- WHEN the stage applies CIColorMatrix to the noise
- THEN each channel vector component SHALL be strength * 0.05 = 0.1

#### Scenario: Dither falls back on failure
- GIVEN a frame where CIRandomGenerator output is nil
- WHEN Dither processes that frame
- THEN the output SHALL be the original frame unchanged

#### Scenario: Dither preserves frame delay
- GIVEN a frame with delay 0.07 seconds
- WHEN Dither processes the frame
- THEN the output frame SHALL have delay 0.07 seconds

#### Scenario: Dither uses GPU-accelerated context
- GIVEN any non-none algorithm
- WHEN Dither creates a CIContext
- THEN it SHALL set useSoftwareRenderer to false

#### Scenario: All dither algorithms except none apply noise
- GIVEN Dither initialized with algorithm: .ordered
- WHEN the stage processes frames
- THEN it SHALL apply the same CIRandomGenerator + CIColorMatrix + CIAdditionCompositing chain as floydSteinberg

### Requirement: FilterStage

The `FilterStage` SHALL apply a chain of Core Image filters to each frame. It accepts an array of (name, params) tuples. Filters SHALL be applied lazily via `CIImage.applyingFilter` chaining. The stage MUST use a GPU-accelerated `CIContext` with `useSoftwareRenderer: false`. If the final `createCGImage` call returns nil for a frame, that frame SHALL be silently dropped from the output.

#### Scenario: Single filter applied
- GIVEN FilterStage with filters: [("CIPhotoEffectMono", [:])]
- WHEN the stage processes a frame
- THEN the output frame image SHALL have the mono effect applied

#### Scenario: Multiple filters chained in order
- GIVEN FilterStage with filters: [("CISharpenLuminance", ["inputSharpness": 0.8]), ("CIVignette", ["inputIntensity": 1.5])]
- WHEN the stage processes a frame
- THEN sharpen SHALL be applied first, followed by vignette

#### Scenario: Frame silently dropped on render failure
- GIVEN a frame that causes CIContext.createCGImage to return nil
- WHEN FilterStage processes that frame
- THEN that frame SHALL NOT appear in the output array

#### Scenario: FilterStage uses GPU context
- GIVEN any valid filter chain
- WHEN FilterStage creates its CIContext
- THEN it SHALL set useSoftwareRenderer to false

#### Scenario: FilterStage preserves frame delay
- GIVEN a frame with delay 0.1 seconds
- WHEN FilterStage processes the frame successfully
- THEN the output frame SHALL have delay 0.1 seconds

#### Scenario: FilterStage yields between frames
- GIVEN 50 frames to filter
- WHEN FilterStage processes each frame
- THEN the stage SHALL call `await Task.yield()` after each successfully processed frame

### Requirement: Crop Stage

The `Crop` stage SHALL crop every frame to the specified `CGRect` using `CGImage.cropping(to:)`. Frames that fail to crop (where `cropping` returns nil) SHALL be silently omitted from the output. Each cropped frame MUST preserve the original frame's `delay` value.

#### Scenario: Successful crop to specified rect
- GIVEN a frame of size 640x480
- WHEN Crop is initialized with rect CGRect(x: 100, y: 100, width: 200, height: 200) and processes the frame
- THEN the output frame image SHALL be 200x200

#### Scenario: Crop preserves frame delay
- GIVEN a frame with delay 0.15 seconds
- WHEN Crop processes the frame
- THEN the output frame SHALL have delay 0.15 seconds

#### Scenario: Failed crop silently omitted
- GIVEN a frame where CGImage.cropping(to:) returns nil for the given rect
- WHEN Crop processes the frame
- THEN that frame SHALL NOT appear in the output array

#### Scenario: Crop processes all frames in batch
- GIVEN 10 frames
- WHEN Crop processes them with a valid rect
- THEN all 10 frames SHALL be cropped (assuming none fail)

### Requirement: Reverse Stage

The `Reverse` stage SHALL reverse the order of the frame array. It MUST NOT modify individual frames. The operation SHALL be purely a reordering of the array.

#### Scenario: Frames reversed in order
- GIVEN frames with delays [0.1, 0.2, 0.3]
- WHEN Reverse processes the frames
- THEN the output delays SHALL be [0.3, 0.2, 0.1]

#### Scenario: Single frame unchanged
- GIVEN a single frame
- WHEN Reverse processes it
- THEN the output SHALL contain that same single frame

#### Scenario: Empty input yields empty output
- GIVEN an empty frame array
- WHEN Reverse processes it
- THEN the output SHALL be an empty array

#### Scenario: Reverse preserves frame identity
- GIVEN 3 frames with specific CGImage references
- WHEN Reverse processes them
- THEN the output SHALL contain the same CGImage references in reversed order

### Requirement: Speed Stage

The `Speed` stage SHALL adjust animation speed by dividing each frame's delay by a multiplier. A multiplier greater than 1.0 SHALL produce faster playback. A multiplier less than 1.0 SHALL produce slower playback. The stage MUST create new `Frame` instances with the adjusted delay while preserving the original `CGImage`.

#### Scenario: Speed multiplier of 2.0 halves delays
- GIVEN frames with delays [0.1, 0.2, 0.3]
- WHEN Speed is initialized with multiplier: 2.0 and processes the frames
- THEN the output delays SHALL be [0.05, 0.1, 0.15]

#### Scenario: Speed multiplier of 0.5 doubles delays
- GIVEN frames with delays [0.1, 0.2]
- WHEN Speed is initialized with multiplier: 0.5 and processes the frames
- THEN the output delays SHALL be [0.2, 0.4]

#### Scenario: Speed preserves image data
- GIVEN a frame with a specific CGImage
- WHEN Speed processes the frame with any multiplier
- THEN the output frame SHALL reference the same CGImage

#### Scenario: Speed multiplier of 1.0 leaves delays unchanged
- GIVEN frames with delays [0.1, 0.2, 0.3]
- WHEN Speed is initialized with multiplier: 1.0 and processes the frames
- THEN the output delays SHALL be [0.1, 0.2, 0.3]

### Requirement: RemoveBackground Stage

The `RemoveBackground` stage SHALL use Apple's Vision framework to perform person segmentation and remove backgrounds. It MUST use `VNGeneratePersonSegmentationRequest` with `.accurate` quality level. If no person is detected (pixel buffer format type is 0 or no result is returned), the stage SHALL return the original frame unchanged. The stage SHALL composite the segmented person over a transparent background using `CIBlendWithMask` with `CIImage.empty()` as the background and the segmentation mask as the mask input. The `CIContext` SHALL use GPU rendering with `useSoftwareRenderer: false`.

#### Scenario: Person detected and background removed
- GIVEN a frame containing a clearly visible person
- WHEN RemoveBackground processes the frame
- THEN the output SHALL have the person preserved with a transparent background

#### Scenario: No person detected returns original
- GIVEN a frame containing only a landscape with no person
- WHEN RemoveBackground processes the frame and Vision detects no person
- THEN the output SHALL be the original frame image unchanged

#### Scenario: Segmentation request uses accurate quality
- GIVEN any input frame
- WHEN RemoveBackground creates VNGeneratePersonSegmentationRequest
- THEN the qualityLevel SHALL be set to .accurate

#### Scenario: Mask scaled to match image dimensions
- GIVEN a frame of 640x480 and a segmentation mask of different dimensions
- WHEN RemoveBackground applies the mask
- THEN the mask SHALL be transformed via CGAffineTransform to match the frame extent

#### Scenario: Background composited as transparent
- GIVEN a frame with a detected person
- WHEN RemoveBackground composites the result
- THEN the background input to CIBlendWithMask SHALL be CIImage.empty()

#### Scenario: RemoveBackground preserves frame delay
- GIVEN a frame with delay 0.1 seconds
- WHEN RemoveBackground processes the frame
- THEN the output frame SHALL have delay 0.1 seconds

### Requirement: Filter Presets

The system SHALL provide 11 filter presets via the `FilterPreset` enum. Each preset SHALL map to a Core Image filter name. Presets with tunable parameters SHALL accept an intensity value (0–1) that scales the filter parameter. Presets without tunable parameters (Chrome, Fade, Mono, Noir, Process, Transfer) SHALL ignore the intensity value. The `toStage(intensity:)` method SHALL return `nil` for the `.none` preset and a `FilterStage` for all other presets.

#### Scenario: None preset returns nil stage
- GIVEN FilterPreset.none
- WHEN toStage(intensity:) is called
- THEN the result SHALL be nil

#### Scenario: Chrome maps to CIPhotoEffectChrome
- GIVEN FilterPreset.chrome
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectChrome" with empty parameters

#### Scenario: Fade maps to CIPhotoEffectFade
- GIVEN FilterPreset.fade
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectFade" with empty parameters

#### Scenario: Mono maps to CIPhotoEffectMono
- GIVEN FilterPreset.mono
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectMono" with empty parameters

#### Scenario: Noir maps to CIPhotoEffectNoir
- GIVEN FilterPreset.noir
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectNoir" with empty parameters

#### Scenario: Process maps to CIPhotoEffectProcess
- GIVEN FilterPreset.process
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectProcess" with empty parameters

#### Scenario: Transfer maps to CIPhotoEffectTransfer
- GIVEN FilterPreset.transfer
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPhotoEffectTransfer" with empty parameters

#### Scenario: Pixelate scales inputScale by intensity
- GIVEN FilterPreset.pixelate and intensity: 0.5
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIPixellate" with inputScale = 0.5 * 20 = 10

#### Scenario: Pixelate at full intensity
- GIVEN FilterPreset.pixelate and intensity: 1.0
- WHEN toStage(intensity:) is called
- THEN inputScale SHALL be 20

#### Scenario: Blur scales inputRadius by intensity
- GIVEN FilterPreset.blur and intensity: 0.5
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIGaussianBlur" with inputRadius = 0.5 * 10 = 5

#### Scenario: Blur at full intensity
- GIVEN FilterPreset.blur and intensity: 1.0
- WHEN toStage(intensity:) is called
- THEN inputRadius SHALL be 10

#### Scenario: Sharpen sets inputSharpness to intensity
- GIVEN FilterPreset.sharpen and intensity: 0.7
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CISharpenLuminance" with inputSharpness = 0.7

#### Scenario: Vignette scales inputIntensity by double
- GIVEN FilterPreset.vignette and intensity: 0.5
- WHEN toStage(intensity:) is called
- THEN the resulting FilterStage SHALL use "CIVignette" with inputIntensity = 0.5 * 2 = 1.0

#### Scenario: Vignette at full intensity
- GIVEN FilterPreset.vignette and intensity: 1.0
- WHEN toStage(intensity:) is called
- THEN inputIntensity SHALL be 2.0

#### Scenario: Intensity slider range is 0 to 1
- GIVEN any tunable filter preset
- WHEN intensity values range from 0 to 1
- THEN the computed filter parameters SHALL scale proportionally within their defined ranges

### Requirement: GPU Acceleration

All processing stages that use Core Image SHALL create their `CIContext` with `useSoftwareRenderer: false` to ensure GPU-accelerated rendering. This applies to `Quantize`, `Dither`, `FilterStage`, and `RemoveBackground`.

#### Scenario: Quantize uses GPU rendering
- GIVEN Quantize stage processing frames
- WHEN it creates a CIContext
- THEN useSoftwareRenderer SHALL be false

#### Scenario: Dither uses GPU rendering
- GIVEN Dither stage with a non-none algorithm
- WHEN it creates a CIContext
- THEN useSoftwareRenderer SHALL be false

#### Scenario: FilterStage uses GPU rendering
- GIVEN FilterStage processing frames
- WHEN it creates a CIContext
- THEN useSoftwareRenderer SHALL be false

#### Scenario: RemoveBackground uses GPU rendering
- GIVEN RemoveBackground compositing the masked output
- WHEN it creates a CIContext
- THEN useSoftwareRenderer SHALL be false

### Requirement: Fallback Behavior

Processing stages that use Core Image filters SHALL gracefully handle filter creation or rendering failures. When a filter cannot be created or an image cannot be rendered, stages SHALL return the original frame rather than throwing an error, except for `Resize` which throws `ProcessingError.resizeFailed`.

#### Scenario: Quantize falls back to original on filter failure
- GIVEN a frame where CIColorPosterize filter creation fails
- WHEN Quantize processes the frame
- THEN the output SHALL be the original unmodified frame

#### Scenario: Dither falls back to original on noise generation failure
- GIVEN a frame where CIRandomGenerator returns nil output
- WHEN Dither processes the frame
- THEN the output SHALL be the original unmodified frame

#### Scenario: FilterStage drops frames on render failure
- GIVEN a frame where CIContext.createCGImage returns nil
- WHEN FilterStage processes the frame
- THEN that frame SHALL be omitted from the output array

#### Scenario: Crop drops frames on cropping failure
- GIVEN a frame where CGImage.cropping(to:) returns nil
- WHEN Crop processes the frame
- THEN that frame SHALL be omitted from the output array

#### Scenario: RemoveBackground returns original when no person detected
- GIVEN a frame where Vision segmentation finds no person
- WHEN RemoveBackground processes the frame
- THEN the output SHALL be the original unmodified frame

### Requirement: Cooperative Frame Processing

Processing stages that iterate over frames SHALL yield between frames using `await Task.yield()` to maintain cooperative concurrency. This applies to `Resize`, `Quantize`, `Dither`, and `FilterStage`. Stages that perform simple array transformations (`Crop`, `Reverse`, `Speed`) are not required to yield.

#### Scenario: Resize yields between frames
- GIVEN multiple frames to resize
- WHEN Resize processes each frame
- THEN it SHALL call `await Task.yield()` after each frame

#### Scenario: Quantize yields between frames
- GIVEN multiple frames to quantize
- WHEN Quantize processes each frame
- THEN it SHALL call `await Task.yield()` after each frame

#### Scenario: Dither yields between frames
- GIVEN multiple frames to dither with a non-none algorithm
- WHEN Dither processes each frame
- THEN it SHALL call `await Task.yield()` after each frame

#### Scenario: FilterStage yields between frames
- GIVEN multiple frames to filter
- WHEN FilterStage processes each frame
- THEN it SHALL call `await Task.yield()` after each frame