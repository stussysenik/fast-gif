# Kernel — Delta

## MODIFIED Requirements

### Requirement: Pipeline Configuration

The system SHALL define a single `buildPipeline(scale:)` function that is the sole
source of the processing stage list. Both the preview and export paths SHALL be derived
from it; they MAY differ only in resolution (`scale`) and frame sampling, never in which
stages run. Quantization and dithering SHALL NOT appear as Swift stages — they are owned
by the Rust core so the two paths cannot diverge.

#### Scenario: One pipeline definition
- GIVEN the preview path and the export path
- WHEN each builds its pipeline
- THEN both SHALL call `buildPipeline(scale:)` and contain the identical ordered stage
  list, differing only in the `scale` argument and the set of frames processed

### Requirement: WYSIWYG Preview

The preview SHALL be **always-exact**: the frame shown at the playhead SHALL be the real
quantized output (via `fastgif_preview_frame`), never a faked approximation. During rapid
edits the displayed frame MAY be briefly stale but MUST NOT be a lie. The preview SHALL
route through the same NeuQuant + nearest-index path as export.

#### Scenario: Preview equals export for the shown frame
- GIVEN the playhead on frame F with a color count C and `Quality.draft`
- WHEN the preview renders F
- THEN F's color set SHALL equal the color set export would produce for F at C/draft

#### Scenario: Staleness, not falseness
- GIVEN a fast sequence of slider changes
- WHEN the latest exact frame has not yet finished computing
- THEN the preview SHALL continue showing the most recent EXACT frame (possibly stale),
  and SHALL NOT show an approximation that differs from any real export

### Requirement: Export

The `export()` method SHALL thread the selected color count and `Quality` preset to the
encoder, run `buildPipeline(.export)`, then encode via the GIF global-palette FFI. The
blocking FFI call SHALL run on a background executor, never on the MainActor's thread, so
the UI cannot stall during export.

#### Scenario: Parameters reach the encoder
- GIVEN a color count and quality selected in the UI
- WHEN `export()` runs
- THEN both values SHALL be passed through to `Encoder.encode(...)` and onward to the FFI

#### Scenario: Export does not block the main thread
- GIVEN a large frame set being exported
- WHEN the FFI encode is in progress
- THEN it SHALL execute off the MainActor and the UI SHALL remain responsive

### Requirement: Frame Management Operations

Frame mutations — including reorder (`moveFrame`) and per-frame delay edits
(`updateFrameDelay`) — SHALL schedule a preview refresh so the displayed result never
goes stale relative to the document.

#### Scenario: Reorder refreshes preview
- GIVEN frames displayed in the preview
- WHEN `moveFrame` reorders them
- THEN `schedulePreview()` SHALL be invoked and the preview SHALL reflect the new order

#### Scenario: Delay edit refreshes preview
- GIVEN a frame's delay is changed via `updateFrameDelay`
- WHEN the edit is applied
- THEN `schedulePreview()` SHALL be invoked and total duration SHALL update

### Requirement: Debouncing Behavior

Preview scheduling SHALL use a monotonically increasing generation token in addition to
debouncing. Each scheduled computation SHALL capture the current token; its result SHALL
be applied ONLY if its token is still the latest when it completes. This SHALL eliminate
the race where a slower older computation overwrites a newer result.

#### Scenario: Stale result is discarded
- GIVEN preview computation A (token 1) is in flight when edit B (token 2) is scheduled
- WHEN A finishes after B
- THEN A's result SHALL be discarded because its token is no longer the latest, and only
  B's result SHALL be displayed

### Requirement: Video Import with Trim

Video import SHALL enforce a hard maximum duration (frame-array memory model; unlimited
duration is deferred). When a source exceeds the cap, the import SHALL clamp to the cap
and surface the reason to the user rather than failing silently or risking an
out-of-memory crash. Trim bounds SHALL snap to frame boundaries.

#### Scenario: Duration cap enforced
- GIVEN a source clip longer than the configured cap
- WHEN it is imported
- THEN the imported range SHALL be clamped to the cap and the UI SHALL explain that the
  clip was trimmed to the maximum supported length

#### Scenario: Trim snaps to frames
- GIVEN a trim handle dragged to an arbitrary time
- WHEN the handle is released
- THEN `trimStart`/`trimEnd` SHALL snap to the nearest frame boundary

## ADDED Requirements

### Requirement: Snap-to-Truth Preview State

The system SHALL retain the last exact preview frame so that, when a freshly computed
exact frame arrives, the UI can transition from the previous exact frame to the new one.
This retained frame is the source for the snap-to-truth transition.

#### Scenario: Last-exact frame retained
- GIVEN an exact preview frame is displayed
- WHEN a new edit produces a new exact frame
- THEN the previous exact frame SHALL still be available as the transition's starting image
