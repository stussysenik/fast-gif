# Kernel Specification

## Purpose

The kernel layer defines the pipeline architecture, data models, and project state
that form the backbone of FastGIF. It provides a composable, cancellable processing
pipeline built on Swift's `@resultBuilder`, immutable frame and document models, and
a single-source-of-truth project class that bridges async processing with the
`@Observable` UI layer.

## Requirements

### Requirement: Stage Protocol Contract

Every processing stage SHALL conform to the `Stage` protocol, which defines a single
async-throwing method that accepts an array of frames and returns a transformed array
of frames. Stages MUST be composable, testable, and independently deployable. A stage
SHALL NOT mutate the input frames array directly; it MUST produce a new array.

#### Scenario: Conforming type processes frames

- GIVEN a type that conforms to `Stage`
- WHEN `process(_ frames: [Frame]) async throws -> [Frame]` is invoked with a non-empty frame array
- THEN the stage SHALL return a new `[Frame]` array containing the transformed output
- AND the original input array SHALL remain unchanged

#### Scenario: Stage throws on failure

- GIVEN a stage that encounters an unrecoverable error during processing
- WHEN `process(_:)` is called
- THEN the stage MUST throw an error describing the failure

### Requirement: Pipeline Result Builder

The `PipelineBuilder` result builder SHALL support all six standard builder methods
so that pipelines can be composed declaratively with conditionals, optionals, and
loops. The builder MUST flatten all contributed stages into a single `[any Stage]`
array.

#### Scenario: Build expression from single stage

- GIVEN a single `Stage` value inside a `@PipelineBuilder` closure
- WHEN `buildExpression` is called
- THEN it SHALL wrap that stage in a single-element array `[stage]`

#### Scenario: Build block from multiple stages

- GIVEN multiple `[any Stage]` arrays produced by expressions
- WHEN `buildBlock` is called with those arrays
- THEN it SHALL flatten all arrays into a single `[any Stage]` array using `flatMap`

#### Scenario: Build optional stage

- GIVEN an optional `[any Stage]` value
- WHEN `buildOptional` is called
- THEN it SHALL return the wrapped array if non-nil, otherwise an empty array

#### Scenario: Build either branch

- GIVEN two possible `[any Stage]` arrays from a conditional
- WHEN `buildEither(first:)` or `buildEither(second:)` is called
- THEN it SHALL return the provided stage array unchanged

#### Scenario: Build array from loop

- GIVEN an array of `[any Stage]` arrays produced by a loop
- WHEN `buildArray` is called
- THEN it SHALL flatten all arrays into a single `[any Stage]` array

### Requirement: Pipeline Composition and Execution

A `Pipeline` struct SHALL hold an ordered list of stages. The `run(_:)` and
`run(_:progress:)` methods MUST execute stages sequentially, passing the output of
each stage as the input to the next. Both methods MUST check for task cancellation
before processing each stage.

#### Scenario: Sequential stage execution

- GIVEN a pipeline with stages `[A, B, C]` and an input frame array
- WHEN `run(_:)` is invoked
- THEN the pipeline SHALL pass the input through A, then B's output through C
- AND the final result of C SHALL be returned

#### Scenario: Progress reporting

- GIVEN a pipeline with N stages
- WHEN `run(_:progress:)` is invoked
- THEN the progress callback SHALL be invoked with `i / N` before processing stage `i`
- AND after all stages complete, progress SHALL be called with `1.0`

#### Scenario: Pipeline with no stages

- GIVEN a pipeline initialized with an empty stages array
- WHEN `run(_:)` is invoked with a frame array
- THEN the original frame array SHALL be returned unchanged

#### Scenario: Pipeline preserves frame delays

- GIVEN stages that transform frame images but do not modify delays
- WHEN the pipeline runs
- THEN each output frame SHALL retain the delay value from its corresponding input frame

### Requirement: Pipeline Cancellation

Both `run` methods MUST call `Task.checkCancellation()` between stages. If the
task is cancelled, the pipeline SHALL throw a `CancellationError` without processing
further stages.

#### Scenario: Cancellation between stages

- GIVEN a pipeline with stages `[A, B, C]` where the parent task is cancelled after stage A completes
- WHEN the pipeline attempts to proceed to stage B
- THEN `Task.checkCancellation()` SHALL throw a `CancellationError`
- AND stages B and C SHALL NOT execute

#### Scenario: Cancellation during progress run

- GIVEN a pipeline running with a progress callback
- WHEN the task is cancelled after stage 2 of 5
- THEN the progress callback SHALL have been invoked with `0.0` and `0.4`
- AND the pipeline SHALL throw `CancellationError` before invoking the callback with `0.6`

### Requirement: Passthrough Identity Stage

The `Passthrough` struct SHALL conform to `Stage` and return its input array
unchanged. It SHALL serve as a no-op placeholder in pipelines.

#### Scenario: Passthrough preserves frames

- GIVEN a `Passthrough` stage and an array of 10 frames
- WHEN `process(_:)` is called
- THEN it SHALL return the identical array with the same frame objects

### Requirement: Frame Data Model

The `Frame` struct SHALL be the atomic unit of animation data. Each frame MUST carry
a unique identifier, a `CGImage`, and a delay in seconds. The struct SHALL provide
computed accessors for image dimensions.

#### Scenario: Frame default delay

- GIVEN a `Frame` constructed with only a `CGImage` and no explicit delay
- WHEN the frame is created
- THEN `delay` SHALL default to `0.1` seconds

#### Scenario: Frame unique identifier

- GIVEN two `Frame` instances created with identical images and delays
- WHEN their `id` properties are compared
- THEN the identifiers SHALL be different, as each frame generates a new `UUID`

#### Scenario: Frame computed dimensions

- GIVEN a `Frame` with a `CGImage` that is 320×240 pixels
- WHEN `width`, `height`, and `size` are accessed
- THEN `width` SHALL be 320, `height` SHALL be 240
- AND `size` SHALL be `CGSize(width: 320, height: 240)`

### Requirement: GIFDocument Container

The `GIFDocument` struct SHALL hold an ordered array of frames and a loop count. It
MUST provide computed properties for total duration and frame count. The default loop
count SHALL be 0 (infinite loop).

#### Scenario: Default document

- GIVEN a `GIFDocument` created with no arguments
- WHEN `frames` is accessed, it SHALL be an empty array
- AND `loopCount` SHALL be 0
- AND `duration` SHALL be 0.0
- AND `frameCount` SHALL be 0

#### Scenario: Duration calculation

- GIVEN a `GIFDocument` with three frames having delays `[0.1, 0.2, 0.15]`
- WHEN `duration` is computed
- THEN it SHALL return `0.45`

#### Scenario: Frame count

- GIVEN a `GIFDocument` with 42 frames
- WHEN `frameCount` is accessed
- THEN it SHALL return 42

### Requirement: GIFProject as Single Source of Truth

`GIFProject` SHALL be a `@MainActor @Observable` class that serves as the single
source of truth for the entire application. It MUST hold the `GIFDocument`, pipeline
configuration, UI state, trim state, and preview state. All mutations SHALL occur on
the main actor. All pipeline work MUST execute asynchronously on the cooperative
thread pool.

#### Scenario: MainActor isolation

- GIVEN a `GIFProject` instance
- WHEN any property is read or written from a non-main-actor context
- THEN the access SHALL be redirected to the main actor via Swift concurrency

#### Scenario: Observable UI updates

- GIVEN a `GIFProject` with a bound SwiftUI view
- WHEN a published property such as `previewFrames` or `isProcessing` changes
- THEN the SwiftUI view SHALL re-render to reflect the new state

#### Scenario: Reset clears all state

- GIVEN a `GIFProject` with frames, processing state, and preview frames
- WHEN `reset()` is called
- THEN `document` SHALL be replaced with a default empty `GIFDocument`
- AND `previewFrames` SHALL be cleared to `[]`
- AND `selectedFrameIndex` SHALL be nil
- AND `isProcessing`, `isImporting`, `importProgress`, `progress`, `currentTime` SHALL be reset to zero/false
- AND `error` SHALL be nil
- AND all in-flight tasks (`previewTask`, `importTask`, `retrimTask`) SHALL be cancelled

### Requirement: Pipeline Configuration

`GIFProject` SHALL expose pipeline configuration properties that control how frames
are processed. Changing any configuration property SHALL automatically trigger a
debounced preview update. The pipeline SHALL be constructed from the current
configuration by `buildPipeline()`.

#### Scenario: Default configuration values

- GIVEN a newly initialized `GIFProject`
- THEN `quantizeColors` SHALL be 256
- AND `ditherAlgorithm` SHALL be `.floydSteinberg`
- AND `ditherStrength` SHALL be 1.0
- AND `speed` SHALL be 1.0
- AND `loopCount` SHALL be 0
- AND `maxWidth` SHALL be nil
- AND `backgroundRemoved` SHALL be false
- AND `filterPreset` SHALL be `.none`
- AND `filterIntensity` SHALL be 1.0

#### Scenario: Configuration change triggers preview

- GIVEN a `GIFProject` with existing frames
- WHEN `quantizeColors` is changed to 128
- THEN `schedulePreview()` SHALL be invoked via the `didSet` observer
- AND a debounced preview update SHALL be scheduled after 300ms

#### Scenario: Pipeline built from configuration

- GIVEN a `GIFProject` with `maxWidth = 480`, `speed = 2.0`, `filterPreset = .blur`, `quantizeColors = 128`, `ditherAlgorithm = .ordered`, `ditherStrength = 0.8`
- WHEN `buildPipeline()` is called
- THEN the resulting pipeline SHALL contain stages in order: `Resize(480)`, `Speed(2.0)`, `FilterStage(blur)`, `Quantize(128)`, `Dither(ordered, 0.8)`

#### Scenario: Pipeline omits optional stages when not configured

- GIVEN a `GIFProject` with `maxWidth = nil`, `speed = 1.0`, `filterPreset = .none`
- WHEN `buildPipeline()` is called
- THEN the pipeline SHALL contain only `Quantize` and `Dither` stages
- AND `Resize`, `Speed`, and `FilterStage` SHALL NOT be present

### Requirement: WYSIWYG Preview

`GIFProject` SHALL maintain a `previewFrames` array that shows what the user's GIF
will look like after processing. The preview MUST run at reduced resolution (240px)
with a maximum of 30 sampled frames for performance. The preview pipeline SHALL NOT
include dither to keep preview generation fast.

#### Scenario: Preview sampling

- GIVEN a `GIFProject` with 120 frames
- WHEN `updatePreview()` is called
- THEN the preview SHALL sample exactly 30 frames distributed evenly across the full set
- AND the sampled frames SHALL be processed through the preview pipeline

#### Scenario: Preview sampling with few frames

- GIVEN a `GIFProject` with 15 frames
- WHEN `updatePreview()` is called
- THEN all 15 frames SHALL be processed (no subsampling needed)

#### Scenario: Preview pipeline composition

- GIVEN a `GIFProject` with frames and configuration
- WHEN `updatePreview()` executes
- THEN the preview pipeline SHALL include `Resize(to: 240)`, optional `Speed`, optional `FilterStage`, and `Quantize`
- AND the preview pipeline SHALL NOT include `Dither`

#### Scenario: Preview cancellation guard

- GIVEN a preview update that has started processing
- WHEN the task is cancelled before completion
- THEN `previewFrames` SHALL NOT be updated with partial results

#### Scenario: Preview with no frames

- GIVEN a `GIFProject` with an empty document
- WHEN `updatePreview()` is called
- THEN `previewFrames` SHALL be set to an empty array

### Requirement: Export

`GIFProject` SHALL provide an `export()` method that runs the full pipeline at
original resolution, then encodes the result. Export progress MUST be reported as
80% for pipeline execution and the final 20% for encoding.

#### Scenario: Successful export

- GIVEN a `GIFProject` with frames and a configured pipeline
- WHEN `export()` is called
- THEN the pipeline SHALL run on the full frame set at original resolution
- AND progress SHALL be reported as pipeline progress × 0.8 during processing
- AND progress SHALL jump to 0.8 after pipeline completion
- AND progress SHALL reach 1.0 after encoding
- AND the encoded `Data` SHALL be returned

#### Scenario: Export error handling

- GIVEN a `GIFProject` with frames
- WHEN `export()` is called and the pipeline throws an error
- THEN `isProcessing` SHALL be reset to `false` (via defer)
- AND `error` SHALL be set to the error's localized description
- AND the error SHALL be re-thrown to the caller

#### Scenario: Export state management

- GIVEN a `GIFProject` that is not currently processing
- WHEN `export()` is called
- THEN `isProcessing` SHALL be set to `true` at the start
- AND `progress` SHALL be reset to 0
- AND `error` SHALL be cleared to nil
- AND `isProcessing` SHALL be reset to `false` upon completion (via defer)

### Requirement: Video Import with Trim

`GIFProject` SHALL support importing video from a URL with configurable FPS, start
time, and end time. Trim state SHALL be maintained as `trimStart` (default 0) and
`trimEnd` (optional, default nil meaning full duration). A `scheduleRetrim()` method
SHALL debounce re-import at 600ms.

#### Scenario: Video import with defaults

- GIVEN a `GIFProject` and a valid video URL with 30 seconds of content
- WHEN `importVideo(url:fps:)` is called with `fps: 10` and no custom trim range
- THEN the video SHALL be decoded starting from `trimStart` (0) to the full duration
- AND the resulting frames SHALL replace the current `GIFDocument`
- AND `selectedFrameIndex` SHALL be set to 0
- AND `sourceVideoURL` SHALL be stored
- AND `videoDuration` SHALL be set to the asset duration
- AND a preview update SHALL be triggered

#### Scenario: Video import with trim range

- GIVEN a `GIFProject` with `trimStart = 5.0` and `trimEnd = 15.0`
- WHEN `importVideo(url:fps:)` is called
- THEN the decoder SHALL be invoked with `startTime: 5.0` and `endTime: 15.0`
- AND only the 10-second window of frames SHALL be produced

#### Scenario: Import state management

- GIVEN a `GIFProject` that is not importing
- WHEN `importVideo(url:fps:)` is called
- THEN `isImporting` SHALL be set to `true`
- AND `importProgress` SHALL be reset to 0
- AND `error` SHALL be cleared to nil
- AND `isImporting` SHALL be reset to `false` upon completion (via defer)

#### Scenario: Import progress reporting

- GIVEN a video import in progress
- WHEN the decoder reports progress
- THEN `importProgress` SHALL be updated on the main actor
- AND the progress value SHALL be between 0.0 and 1.0

#### Scenario: Retrim debounce

- GIVEN a `GIFProject` with a stored `sourceVideoURL`
- WHEN `scheduleRetrim()` is called multiple times in rapid succession
- THEN only the last call SHALL result in an actual re-import
- AND the re-import SHALL occur after a 600ms debounce delay
- AND any in-flight `importTask` and prior `retrimTask` SHALL be cancelled

#### Scenario: Retrim without source video

- GIVEN a `GIFProject` with `sourceVideoURL = nil`
- WHEN `scheduleRetrim()` is called
- THEN no import SHALL be triggered after the debounce period

### Requirement: Frame Management Operations

`GIFProject` SHALL provide methods for frame-level manipulation: delete, move,
duplicate, reverse, and update delay. Each mutation that affects visual output SHALL
trigger a preview reschedule.

#### Scenario: Delete frame at valid index

- GIVEN a `GIFProject` with 10 frames and `selectedFrameIndex = 5`
- WHEN `deleteFrame(at: 5)` is called
- THEN the frame at index 5 SHALL be removed
- AND `selectedFrameIndex` SHALL be adjusted to remain valid
- AND `schedulePreview()` SHALL be called

#### Scenario: Delete last frame adjusts selection

- GIVEN a `GIFProject` with 5 frames and `selectedFrameIndex = 4`
- WHEN `deleteFrame(at: 4)` is called
- THEN `selectedFrameIndex` SHALL be updated to 3 (the new last index)

#### Scenario: Delete only frame clears selection

- GIVEN a `GIFProject` with 1 frame and `selectedFrameIndex = 0`
- WHEN `deleteFrame(at: 0)` is called
- THEN `selectedFrameIndex` SHALL be set to nil

#### Scenario: Delete at invalid index is no-op

- GIVEN a `GIFProject` with 5 frames
- WHEN `deleteFrame(at: 10)` is called
- THEN no frame SHALL be removed
- AND no preview SHALL be scheduled

#### Scenario: Move frame

- GIVEN a `GIFProject` with frames `[A, B, C, D, E]`
- WHEN `moveFrame(from: IndexSet(integer: 0), to: 3)` is called
- THEN the frames array SHALL be reordered to `[B, C, A, D, E]`

#### Scenario: Duplicate frame

- GIVEN a `GIFProject` with frames where frame at index 2 has delay 0.15
- WHEN `duplicateFrame(at: 2)` is called
- THEN a new frame with the same image and delay SHALL be inserted at index 3
- AND the new frame SHALL have a different `UUID` than the original
- AND `schedulePreview()` SHALL be called

#### Scenario: Duplicate at invalid index is no-op

- GIVEN a `GIFProject` with 5 frames
- WHEN `duplicateFrame(at: 10)` is called
- THEN no frame SHALL be added

#### Scenario: Reverse frames

- GIVEN a `GIFProject` with frames `[A, B, C]`
- WHEN `reverseFrames()` is called
- THEN the frames array SHALL become `[C, B, A]`
- AND `schedulePreview()` SHALL be called

#### Scenario: Update frame delay

- GIVEN a `GIFProject` with frames where frame at index 1 has delay 0.1
- WHEN `updateFrameDelay(at: 1, delay: 0.25)` is called
- THEN frame 1's delay SHALL be updated to 0.25
- AND no preview reschedule SHALL occur (delay changes don't affect visuals)

#### Scenario: Update delay at invalid index is no-op

- GIVEN a `GIFProject` with 5 frames
- WHEN `updateFrameDelay(at: 10, delay: 0.5)` is called
- THEN no frame SHALL be modified

### Requirement: Debouncing Behavior

`GIFProject` SHALL debounce preview updates at 300ms and retrim operations at 600ms.
Each debounced call MUST cancel the previous in-flight task before scheduling a new
one with the specified delay.

#### Scenario: Preview debounce coalesces rapid changes

- GIVEN a `GIFProject` with frames
- WHEN `schedulePreview()` is called three times within 100ms
- THEN only one preview update SHALL execute after the final call's 300ms delay
- AND the earlier two scheduled updates SHALL be cancelled

#### Scenario: Preview task cancellation guard

- GIVEN a scheduled preview that has waited 300ms and started executing
- WHEN the task was cancelled during the sleep period
- THEN `Task.isCancelled` SHALL be true and `updatePreview()` SHALL NOT execute

#### Scenario: Retrim debounce at 600ms

- GIVEN a `GIFProject` with a `sourceVideoURL`
- WHEN `scheduleRetrim()` is called
- THEN the retrim SHALL wait 600ms before executing
- AND any previous `retrimTask` and `importTask` SHALL be cancelled first

#### Scenario: All tasks cancelled on reset

- GIVEN a `GIFProject` with an active preview task, import task, and retrim task
- WHEN `reset()` is called
- THEN all three tasks SHALL be cancelled immediately