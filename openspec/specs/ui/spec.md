# UI Specification

## Purpose
This specification describes the current user-facing behavior of the FastGIF iOS app's UI layer. FastGIF is a GIF and animated image editor that allows users to import videos, photos, and files; edit them with WYSIWYG previews; apply filters and color quantization; and export in multiple formats including GIF, APNG, WebP, MP4, MOV, and HEIC. The UI follows an iA Writer-inspired minimal design system.

## Requirements

### Requirement: App Entry Point
The app SHALL present a `WindowGroup` containing `ContentView` as its root scene. The app SHALL be marked with `@main`.

#### Scenario: App launch
- GIVEN the app is installed on a device
- WHEN the user launches FastGIF
- THEN the app SHALL display the `ContentView` as the root view inside a `WindowGroup`

---

### Requirement: Tab-Based Navigation
The app SHALL display a `TabView` with two tabs: "Create" and "Batch". The active tab SHALL be tracked via internal state. The same `GIFProject` instance SHALL be shared across both tabs.

#### Scenario: Default tab on launch
- GIVEN the app has just launched
- WHEN the user sees the main interface
- THEN the "Create" tab SHALL be selected by default
- AND the tab bar SHALL display two tabs: "Create" with `wand.and.stars` icon and "Batch" with `square.stack.3d.up` icon

#### Scenario: Switch to Batch tab
- GIVEN the user is on the "Create" tab
- WHEN the user taps the "Batch" tab item
- THEN the app SHALL display `BatchView`
- AND the `GIFProject` instance SHALL be the same object shared with the Create tab

#### Scenario: Switch back to Create tab
- GIVEN the user is on the "Batch" tab
- WHEN the user taps the "Create" tab item
- THEN the app SHALL display the Create tab content
- AND any project state changes made in the Batch tab SHALL be reflected in the Create tab

---

### Requirement: Create Tab State Management
The Create tab SHALL display either `ImportView` or `EditorView` depending on whether the project has frames. The `GIFProject` SHALL be managed as `@State` and wrapped in a `NavigationStack`.

#### Scenario: No frames exist — show ImportView
- GIVEN the user is on the Create tab
- AND the project has no frames
- WHEN the view renders
- THEN the app SHALL display `ImportView` inside a `NavigationStack`
- AND the navigation title SHALL be "FastGIF" with inline display mode
- AND the toolbar SHALL NOT display the "New" button

#### Scenario: Frames exist — show EditorView
- GIVEN the user is on the Create tab
- AND the project has one or more frames
- WHEN the view renders
- THEN the app SHALL display `EditorView` inside a `NavigationStack`
- AND the navigation title SHALL be "FastGIF" with inline display mode
- AND the toolbar SHALL display a "New" button with a `plus` icon in the leading position

#### Scenario: Reset project via New button
- GIVEN the user is on the Create tab
- AND the project has frames
- WHEN the user taps the "New" button
- THEN the project SHALL be reset (all frames cleared, state restored to default)
- AND the view SHALL transition to `ImportView`

---

### Requirement: Import View Layout
`ImportView` SHALL present three import methods centered vertically in the view. The layout SHALL use the Theme spacing system.

#### Scenario: Import view appearance
- GIVEN the project has no frames
- WHEN `ImportView` is displayed
- THEN the view SHALL show a large `plus.rectangle.on.folder` icon at 64pt ultra-light weight
- AND a "Create something" title at `.title2` medium weight below the icon
- AND three import buttons arranged vertically with 12pt spacing
- AND all content SHALL be centered with equal spacers above and below
- AND the button group SHALL have a maximum width of 280pt

---

### Requirement: Video Import via Photos Picker
`ImportView` SHALL provide a `PhotosPicker` for importing a single video from the user's photo library.

#### Scenario: Open video picker
- GIVEN the user is on `ImportView`
- WHEN the user taps "From Video"
- THEN a `PhotosPicker` SHALL be presented filtered to `.videos` content type
- AND the picker SHALL allow a maximum of 1 item selection

#### Scenario: Video selected from photos
- GIVEN the video `PhotosPicker` is open
- WHEN the user selects a video
- THEN the app SHALL load the video data via `loadTransferable`
- AND write the data to a temporary file with `.mp4` extension
- AND call `project.importVideo()` with the temporary URL
- AND clear the selected items array after processing

---

### Requirement: Image Import via Photos Picker
`ImportView` SHALL provide a `PhotosPicker` for importing up to 50 images from the user's photo library.

#### Scenario: Open image picker
- GIVEN the user is on `ImportView`
- WHEN the user taps "From Photos"
- THEN a `PhotosPicker` SHALL be presented filtered to `.images` content type
- AND the picker SHALL allow a maximum of 50 items

#### Scenario: Images selected from photos
- GIVEN the image `PhotosPicker` is open
- WHEN the user selects one or more images
- THEN the app SHALL load each image's data via `loadTransferable`
- AND convert each to `Data` → `UIImage` → `CGImage`
- AND call `project.addFrames()` with all successfully converted images
- AND each frame SHALL have a default delay of 0.1 seconds
- AND clear the selected items array after processing

---

### Requirement: File Import
`ImportView` SHALL provide a file importer button for importing GIF, PNG, and video files from the device filesystem.

#### Scenario: Open file importer
- GIVEN the user is on `ImportView`
- WHEN the user taps "Open File"
- THEN a `fileImporter` SHALL be presented
- AND it SHALL allow content types: `.gif`, `.png`, `.movie`, `.video`, `.mpeg4Movie`
- AND it SHALL NOT allow multiple selection

#### Scenario: Import GIF or PNG file
- GIVEN the file importer is open
- WHEN the user selects a file with `.gif` or `.png` extension (case-insensitive)
- THEN the app SHALL access the security-scoped resource
- AND read the file data
- AND call `project.importImageData()` with the data
- AND stop accessing the security-scoped resource

#### Scenario: Import video file
- GIVEN the file importer is open
- WHEN the user selects a video file (not GIF or PNG)
- THEN the app SHALL access the security-scoped resource
- AND call `project.importVideo()` with the file URL
- AND stop accessing the security-scoped resource

---

### Requirement: Editor View Layout
`EditorView` SHALL present a WYSIWYG editing surface with progressive disclosure of controls. The layout SHALL consist of an animated preview, optional trim bar, time scrubber, and toggleable controls bar.

#### Scenario: Editor view composition
- GIVEN the project has frames
- WHEN `EditorView` is displayed
- THEN the view SHALL show from top to bottom:
  - `AnimatedPreview` in a flexible frame with `Theme.surface` background and medium corner radius
  - `TrimView` (only if `sourceVideoURL` is not nil)
  - `TimeScrubber` at 56pt height
  - `ControlsBar` (only when `showControls` is true)
- AND the preview SHALL be padded with 16pt on all sides

#### Scenario: Toggle controls bar via tap
- GIVEN the editor is displayed
- WHEN the user taps the animated preview area
- THEN the controls bar SHALL toggle visibility
- AND the transition SHALL use `move(edge: .bottom)` combined with opacity
- AND the animation SHALL use `Theme.springSnappy`

---

### Requirement: Editor Toolbar
`EditorView` SHALL display toolbar buttons for Export, Filters, Palette, and Controls. Export, Filters, and Palette buttons SHALL be disabled when no frames exist.

#### Scenario: Toolbar buttons displayed
- GIVEN the editor is displayed with frames
- WHEN the user views the toolbar
- THEN the trailing toolbar SHALL contain buttons: "Export" (`square.and.arrow.up`), "Filters" (`camera.filters`), "Palette" (`paintpalette`), and "Controls" (`slider.horizontal.3`)

#### Scenario: Toolbar buttons disabled without frames
- GIVEN the project has no frames
- WHEN the editor toolbar renders
- THEN the Export, Filters, and Palette buttons SHALL be disabled
- AND the Controls button SHALL remain enabled

#### Scenario: Open Export sheet
- GIVEN the editor is displayed with frames
- WHEN the user taps "Export"
- THEN a sheet SHALL present `ExportView`

#### Scenario: Open Filters sheet
- GIVEN the editor is displayed with frames
- WHEN the user taps "Filters"
- THEN a sheet SHALL present `FilterView`

#### Scenario: Open Palette sheet
- GIVEN the editor is displayed with frames
- WHEN the user taps "Palette"
- THEN a sheet SHALL present `PaletteView`

#### Scenario: Toggle controls via toolbar
- GIVEN the editor is displayed
- WHEN the user taps "Controls"
- THEN the controls bar SHALL toggle visibility

---

### Requirement: Processing Overlay
`EditorView` SHALL display a processing overlay when the project is actively processing (exporting).

#### Scenario: Processing overlay displayed
- GIVEN the editor is displayed
- WHEN `project.isProcessing` is true
- THEN a `ProcessingOverlay` SHALL be displayed as an overlay
- AND it SHALL show a progress bar with value `project.progress`
- AND display the message "Processing…" (with ellipsis character)

#### Scenario: Processing overlay hidden
- GIVEN the editor is displayed
- WHEN `project.isProcessing` is false
- THEN the `ProcessingOverlay` SHALL NOT be displayed

---

### Requirement: Animated Preview Component
`AnimatedPreview` SHALL display frames at their natural timing using a `Timer`. It SHALL handle loading, empty, and animation states.

#### Scenario: Display animated frames
- GIVEN the component receives a non-empty array of frames with more than 1 frame
- WHEN the view appears
- THEN the component SHALL start animating through frames using `Timer.scheduledTimer`
- AND each frame SHALL be displayed for its `delay` duration
- AND the animation SHALL loop back to the first frame after the last
- AND the current frame SHALL be displayed as a resizable image with aspect-fit content mode

#### Scenario: Single frame display
- GIVEN the component receives an array with exactly 1 frame
- WHEN the view appears
- THEN the component SHALL display the single frame without animation

#### Scenario: Loading state
- GIVEN `isLoading` is true
- AND the current frame index is out of bounds
- WHEN the view renders
- THEN a progress bar SHALL be displayed with `Theme.accent` tint at max 160pt width
- AND a "Importing…" label SHALL be shown in caption font with `Theme.textSecondary`

#### Scenario: No frames state
- GIVEN `isLoading` is false
- AND no frames are available for the current index
- WHEN the view renders
- THEN a `ContentUnavailableView` SHALL be displayed with title "No Frames" and `photo.stack` system image

#### Scenario: Time update callback
- GIVEN the animation is running
- WHEN each frame transition occurs
- THEN the `onTimeUpdate` callback SHALL be called with the elapsed time (sum of delays of all frames up to the current index)

#### Scenario: Animation restart on frame count change
- GIVEN the animation is running
- WHEN the number of frames changes
- THEN the animation SHALL restart from the first frame

#### Scenario: Accessibility label on preview
- GIVEN the preview is displaying a frame
- WHEN VoiceOver is active
- THEN the accessibility label SHALL be "Preview, frame {current+1} of {total}"

---

### Requirement: Time Scrubber
`TimeScrubber` SHALL display a time ruler with a draggable playhead, current time, frame count, and total duration.

#### Scenario: Time display formatting
- GIVEN the time scrubber is displayed
- WHEN the current time is less than 60 seconds (e.g., 1.2s)
- THEN the time SHALL be formatted as `{seconds}.{tenths}s` (e.g., "1.2s")
- WHEN the current time is 60 seconds or more (e.g., 62.3s)
- THEN the time SHALL be formatted as `{minutes}:{seconds}.{tenths}` (e.g., "1:02.3")

#### Scenario: Scrubber layout
- GIVEN the time scrubber is displayed
- THEN it SHALL show a top row with: current time (left, monospaced medium), frame count (center, monospaced tertiary), total duration (right, monospaced medium secondary)
- AND a scrub bar consisting of: a capsule track in `Theme.surface`, a filled capsule progress bar in `Theme.accent`, and a circular playhead in `Theme.accent` with shadow

#### Scenario: Drag to seek
- GIVEN the time scrubber is displayed
- WHEN the user drags on the scrub bar
- THEN `project.currentTime` SHALL be updated proportional to the drag position relative to `totalDuration`
- AND the fraction SHALL be clamped between 0 and 1

#### Scenario: Scrubber accessibility
- GIVEN the time scrubber is displayed
- WHEN VoiceOver is active
- THEN the scrubber SHALL have accessibility label "Timeline"
- AND accessibility value "{currentTime} of {totalDuration}"

---

### Requirement: Trim View
`TrimView` SHALL provide a geometry-based trim bar with draggable start and end handles. It SHALL only be displayed when the project has a source video URL.

#### Scenario: Trim view visibility
- GIVEN `EditorView` is displayed
- WHEN `project.sourceVideoURL` is nil
- THEN `TrimView` SHALL NOT be rendered
- WHEN `project.sourceVideoURL` is not nil
- THEN `TrimView` SHALL be rendered

#### Scenario: Trim bar layout
- GIVEN `TrimView` is displayed
- THEN it SHALL show a "Trim" section header and a time range label in the format "start – end"
- AND a trim bar with: a capsule track in `Theme.surface`, a highlighted range capsule in `Theme.accent` at 30% opacity, and two draggable handles

#### Scenario: Drag start handle
- GIVEN `TrimView` is displayed with `videoDuration > 0`
- WHEN the user drags the start handle
- THEN `project.trimStart` SHALL be updated proportionally
- AND the start position SHALL be clamped to not exceed the effective end minus 1% of duration
- WHEN the drag ends
- THEN `onRetrim()` SHALL be called

#### Scenario: Drag end handle
- GIVEN `TrimView` is displayed with `videoDuration > 0`
- WHEN the user drags the end handle
- THEN `project.trimEnd` SHALL be updated proportionally
- AND the end position SHALL be clamped to not be less than `trimStart` plus 1% of duration
- WHEN the drag ends
- THEN `onRetrim()` SHALL be called

#### Scenario: Effective end time fallback
- GIVEN `TrimView` is displayed
- WHEN `project.trimEnd` is nil
- THEN the effective end SHALL default to `project.videoDuration`

#### Scenario: Retrim debounce
- GIVEN the user has finished dragging a trim handle
- WHEN `onRetrim()` is called
- THEN the project SHALL schedule a retrim with a 600ms debounce
- AND any in-flight import tasks SHALL be cancelled
- AND after 600ms of no further changes, the video SHALL be re-imported with the updated trim range

#### Scenario: Trim handle accessibility
- GIVEN `TrimView` is displayed
- WHEN VoiceOver is active
- THEN the start handle SHALL have accessibility label "Trim start" and value formatted as time
- AND the end handle SHALL have accessibility label "Trim end" and value formatted as time

---

### Requirement: Controls Bar
`ControlsBar` SHALL display horizontally scrollable editing controls for speed, color quantization, dither algorithm, and frame reversal.

#### Scenario: Controls bar layout
- GIVEN the controls bar is visible
- THEN it SHALL display a horizontal scroll view with sections for Speed, Colors, Dither, and Actions
- AND each section SHALL have a section header label
- AND dividers SHALL separate each section at 40pt height

#### Scenario: Speed control
- GIVEN the controls bar is visible
- THEN a "Speed" section SHALL display a slider ranging from 0.1 to 5.0
- AND the current speed value SHALL be displayed below in `caption2.monospaced()` format (e.g., "1.0x")
- AND the slider SHALL have accessibility label "Playback speed" and value "{speed}x"

#### Scenario: Color count control
- GIVEN the controls bar is visible
- THEN a "Colors" section SHALL display a segmented picker with options: 16, 32, 64, 128, 256
- AND the picker SHALL be 200pt wide
- AND changing the selection SHALL update `project.quantizeColors`

#### Scenario: Dither algorithm control
- GIVEN the controls bar is visible
- THEN a "Dither" section SHALL display a menu picker with all `DitherAlgorithm` cases (Floyd-Steinberg, Ordered, Bayer, None)
- AND changing the selection SHALL update `project.ditherAlgorithm`

#### Scenario: Reverse frames action
- GIVEN the controls bar is visible
- THEN an "Actions" section SHALL display a "Reverse" button with `arrow.left.arrow.right` icon
- AND the button SHALL use bordered style with small control size
- WHEN tapped
- THEN `project.reverseFrames()` SHALL be called

#### Scenario: Controls bar background
- GIVEN the controls bar is visible
- THEN the background SHALL be `Theme.surface`

---

### Requirement: Export View
`ExportView` SHALL provide format selection, loop count configuration, iMessage sticker wizard access, estimated file size display, save-to-photos, and share functionality.

#### Scenario: Export view navigation
- GIVEN `ExportView` is presented
- THEN it SHALL display inside a `NavigationStack` with title "Export" and inline title display mode
- AND a "Done" cancellation button SHALL be in the toolbar

#### Scenario: Format selection list
- GIVEN `ExportView` is displayed
- THEN all 6 `ExportFormat` cases SHALL be listed in a Format section
- AND each format row SHALL show an icon and display name
- AND the currently selected format SHALL display a checkmark in `Theme.accent`
- AND WebP and HEIC formats SHALL display a "Static" caption in `Theme.textTertiary`
- WHEN the user taps a format row
- THEN `project.exportFormat` SHALL be updated
- AND the estimated size SHALL be reset to nil

#### Scenario: Estimated file size
- GIVEN `ExportView` is displayed with frames available
- WHEN the export format changes
- THEN the app SHALL run the full pipeline and encoder to calculate the estimated output size
- AND the size SHALL be displayed next to the selected format using `ByteCountFormatter`
- AND the size SHALL be shown in monospaced caption font with `Theme.textSecondary`

#### Scenario: Loop count stepper
- GIVEN `ExportView` is displayed
- THEN a Settings section SHALL show a stepper for loop count
- AND the stepper range SHALL be 0 to 100
- AND when the loop count is 0, the display SHALL show "∞" (infinity symbol)
- AND when the loop count is non-zero, the display SHALL show the numeric value

#### Scenario: iMessage Sticker Wizard access
- GIVEN `ExportView` is displayed
- THEN a Stickers section SHALL contain a button labeled "iMessage Sticker Wizard" with `message.badge.waveform` icon
- WHEN tapped
- THEN a sheet SHALL present `StickerWizardView`

#### Scenario: Save to Photos
- GIVEN `ExportView` is displayed with frames
- WHEN the user taps "Save to Photos"
- THEN the app SHALL request `PHPhotoLibrary` authorization for `.addOnly`
- AND if authorization is denied, an error message "Photo library access denied. Enable in Settings." SHALL be displayed
- AND if authorized, the app SHALL export the project, write to a temporary file, and use `PHAssetCreationRequest` to save
- AND the resource type SHALL be `.video` for MP4/MOV formats and `.photo` for all others
- AND on success, a "Saved to Photos" success message with `checkmark.circle.fill` icon in `Theme.success` SHALL be displayed
- AND on failure, the error description SHALL be displayed with `exclamationmark.triangle` icon in `Theme.destructive`

#### Scenario: Save to Photos progress
- GIVEN `ExportView` is displayed and export is in progress
- WHEN `project.isProcessing` is true
- THEN the Save button SHALL display a progress bar at 120pt width and percentage text
- AND the button SHALL be disabled

#### Scenario: Share export
- GIVEN `ExportView` is displayed with frames
- WHEN the user taps "Share {format}"
- THEN the app SHALL export the project data
- AND write it to a temporary file named "FastGIF-{UUID}" with the appropriate extension
- AND present a `UIActivityViewController` via `ActivityView` sheet
- AND on failure, the error description SHALL be displayed

#### Scenario: Export buttons disabled without frames
- GIVEN `ExportView` is displayed
- WHEN `project.hasFrames` is false or `project.isProcessing` is true
- THEN both Save to Photos and Share buttons SHALL be disabled

---

### Requirement: Filter View
`FilterView` SHALL display a horizontal scroll of filter preset chips and an intensity slider when a filter is active.

#### Scenario: Filter chip list
- GIVEN `FilterView` is displayed
- THEN all 11 `FilterPreset` cases SHALL be displayed as horizontally scrollable chips: None, Chrome, Fade, Mono, Noir, Process, Transfer, Pixelate, Blur, Sharpen, Vignette
- AND each chip SHALL display the preset name in caption medium weight
- AND each chip SHALL have capsule shape with 12pt horizontal and 8pt vertical padding
- AND the selected chip SHALL use `Theme.accent` background with white text
- AND unselected chips SHALL use `Theme.surface` background with `Theme.textPrimary` text

#### Scenario: Select a filter
- GIVEN `FilterView` is displayed
- WHEN the user taps a filter chip
- THEN `project.filterPreset` SHALL be updated to the selected preset

#### Scenario: Intensity slider for active filter
- GIVEN `FilterView` is displayed
- WHEN `project.filterPreset` is not `.none`
- THEN an intensity slider SHALL be displayed ranging from 0 to 1
- AND the slider SHALL be labeled "Intensity" in caption font with `Theme.textSecondary`
- WHEN `project.filterPreset` is `.none`
- THEN the intensity slider SHALL NOT be displayed

#### Scenario: Card style container
- GIVEN `FilterView` is displayed
- THEN the entire content SHALL be wrapped in a `CardStyle` modifier (16pt padding, surface background, medium corner radius)

---

### Requirement: Palette View
`PaletteView` SHALL allow extraction of dominant colors from the project's frames and display them in a grid, along with a palette size picker.

#### Scenario: Initial state — no colors extracted
- GIVEN `PaletteView` is displayed
- WHEN no colors have been extracted and extraction is not in progress
- THEN an "Extract Colors" button with `eyedropper` icon SHALL be displayed using bordered style

#### Scenario: Color extraction in progress
- GIVEN the user has triggered color extraction
- WHEN extraction is running
- THEN a `ProgressView` with "Analyzing…" label SHALL be displayed

#### Scenario: Color extraction algorithm
- GIVEN the user triggers extraction
- WHEN extraction runs
- THEN the app SHALL take the first frame
- AND apply `CIColorPosterize` with 6 levels to reduce color complexity
- AND sample approximately 64 evenly-spaced pixels from the posterized image
- AND quantize each pixel's RGB values to 32-step buckets (i.e., `(channel / 32) * 32`)
- AND deduplicate colors using the quantized values
- AND display up to 32 unique colors in the grid

#### Scenario: Color grid display
- GIVEN colors have been extracted
- WHEN the palette view renders the results
- THEN colors SHALL be displayed in a `LazyVGrid` with 8 flexible columns and 4pt spacing
- AND each color SHALL be rendered as a `RoundedRectangle` with corner radius 4 and height 32pt

#### Scenario: Palette size picker
- GIVEN colors have been extracted
- WHEN the palette view renders
- THEN a palette size picker SHALL be displayed with segmented options: 16, 32, 64, 128, 256
- AND the picker SHALL be 220pt wide
- AND the selection SHALL update `project.quantizeColors`

#### Scenario: Card style container
- GIVEN `PaletteView` is displayed
- THEN the content SHALL be wrapped in a `CardStyle` modifier

---

### Requirement: Batch View
`BatchView` SHALL allow the user to select multiple files, configure export settings, and process all files sequentially.

#### Scenario: Batch view navigation
- GIVEN `BatchView` is displayed
- THEN it SHALL be wrapped in a `NavigationStack` with title "Batch"

#### Scenario: Add files
- GIVEN `BatchView` is displayed
- WHEN the user taps "Add Files"
- THEN a `fileImporter` SHALL be presented
- AND it SHALL allow content types: `.gif`, `.png`, `.movie`, `.video`, `.mpeg4Movie`
- AND it SHALL allow multiple selection

#### Scenario: Display selected files
- GIVEN files have been added
- WHEN the batch view renders
- THEN the Input section header SHALL display the file count (e.g., "Input (3 files)")
- AND each file SHALL be listed with its filename and `doc` icon
- AND files SHALL be deletable via swipe-to-delete

#### Scenario: Batch format and color settings
- GIVEN files have been added
- WHEN the settings section renders
- THEN a format picker SHALL display all `ExportFormat` cases
- AND a colors picker SHALL display options: 16, 64, 128, 256
- AND these settings SHALL read from and write to the shared `project` instance

#### Scenario: Process all files
- GIVEN files have been added
- WHEN the user taps "Process All"
- THEN each file SHALL be processed sequentially
- AND the button label SHALL change to "Processing..." during execution
- AND the button SHALL be disabled during processing

#### Scenario: GIF or PNG file processing
- GIVEN batch processing is running
- WHEN a file has `.gif` or `.png` extension (case-insensitive)
- THEN the app SHALL read the file data using security-scoped resource access
- AND decode via `Decoder.decodeImageSource()`
- AND process through the pipeline
- AND encode in the selected format
- AND write the output to the temporary directory with the original filename and new extension

#### Scenario: Video file processing
- GIVEN batch processing is running
- WHEN a file is a video (not GIF or PNG)
- THEN the app SHALL decode via `Decoder.decodeVideo()`
- AND process through the pipeline
- AND encode in the selected format
- AND write the output to the temporary directory

#### Scenario: Batch results display
- GIVEN batch processing has completed
- WHEN the results section renders
- THEN each result SHALL display a success (`checkmark.circle.fill` in `Theme.success`) or failure (`xmark.circle.fill` in `Theme.destructive`) icon
- AND the filename
- AND the output size in human-readable format (via `ByteCountFormatter`) for successful results
- AND the error description for failed results

---

### Requirement: Sticker Wizard View
`StickerWizardView` SHALL provide a two-step wizard for creating iMessage-optimized stickers, with size selection, background removal, and a 500KB size constraint.

#### Scenario: Sticker wizard navigation
- GIVEN `StickerWizardView` is presented
- THEN it SHALL display inside a `NavigationStack` with title "Sticker Wizard" and inline display mode
- AND a "Cancel" button SHALL be in the cancellation action toolbar position

#### Scenario: Sticker preview
- GIVEN `StickerWizardView` is displayed with frames
- THEN an `AnimatedPreview` SHALL be shown at 200×200pt
- AND the background SHALL be a checkerboard pattern (10pt squares) in gray at 20% opacity for transparency visualization
- AND the preview SHALL have medium corner radius

#### Scenario: Sticker size picker
- GIVEN `StickerWizardView` is displayed
- THEN a segmented picker SHALL offer three sizes: Small (300px), Medium (408px), Large (618px)
- AND each segment SHALL show the size name and pixel dimension as caption2

#### Scenario: Background removal toggle
- GIVEN `StickerWizardView` is displayed
- THEN a toggle SHALL be displayed with label "Remove Background" and `person.crop.rectangle` icon

#### Scenario: Two-step workflow — Step 1 Optimize
- GIVEN `StickerWizardView` is displayed
- WHEN no result exists
- THEN the primary button SHALL display "Optimize" with `wand.and.stars` icon
- WHEN the user taps "Optimize"
- THEN the app SHALL optionally apply background removal (if toggle is on)
- AND call `StickerOptimizer.optimize()` with the current sticker size and project loop count

#### Scenario: Sticker optimization algorithm
- GIVEN the optimizer runs
- WHEN processing frames
- THEN it SHALL resize frames to the selected sticker dimensions
- AND cap frame rate at 15 FPS (minimum delay of 1/15s)
- AND attempt APNG encoding first
- AND if over 500KB, progressively halve the color count from 256 down to 16
- AND if still over 500KB, remove every other frame and double remaining delays (minimum 4 frames)

#### Scenario: Result display after optimization
- GIVEN optimization has completed
- WHEN the result is available
- THEN the file size SHALL be displayed using `ByteCountFormatter`
- AND the 500KB limit SHALL be displayed in monospaced font
- AND the file size SHALL be colored `Theme.success` if within limit, `Theme.destructive` if over
- AND if within limit, a "Ready for iMessage" label with `checkmark.circle.fill` in `Theme.success` SHALL appear
- AND if over limit, an "Over size limit — try smaller size or fewer frames" warning with `exclamationmark.triangle` in `Theme.destructive` SHALL appear

#### Scenario: Two-step workflow — Step 2 Export Sticker
- GIVEN optimization has completed and a result exists
- THEN the primary button SHALL display "Export Sticker" with `square.and.arrow.up` icon
- WHEN the user taps "Export Sticker"
- THEN the result data SHALL be written to a temporary file with `.apng` extension
- AND a share sheet (`ActivityView`) SHALL be presented with the file URL

#### Scenario: Optimization in progress
- GIVEN optimization is running
- WHEN `isOptimizing` is true
- THEN the primary button SHALL display a `ProgressView` spinner instead of a label
- AND the button SHALL be disabled

#### Scenario: No frames available
- GIVEN `StickerWizardView` is displayed
- WHEN `project.hasFrames` is false
- THEN the primary button SHALL be disabled

---

### Requirement: Design System — Theme
The app SHALL use a centralized `Theme` enum defining colors, spacing, corner radii, and animations following an iA Writer-inspired minimal design system.

#### Scenario: Color tokens
- GIVEN the Theme system
- THEN the following color tokens SHALL be defined:
  - `background`: `Color(.systemBackground)`
  - `surface`: `Color(.secondarySystemBackground)`
  - `accent`: `Color.blue`
  - `destructive`: `Color.red`
  - `success`: `Color.green`
  - `textPrimary`: `Color(.label)`
  - `textSecondary`: `Color(.secondaryLabel)`
  - `textTertiary`: `Color(.tertiaryLabel)`

#### Scenario: Spacing tokens (4pt grid)
- GIVEN the Theme system
- THEN the following spacing tokens SHALL be defined: 2pt, 4pt, 8pt, 12pt, 16pt, 24pt, 32pt

#### Scenario: Corner radius tokens
- GIVEN the Theme system
- THEN `radiusSmall` SHALL be 6pt, `radiusMedium` SHALL be 12pt, `radiusLarge` SHALL be 20pt

#### Scenario: Animation tokens
- GIVEN the Theme system
- THEN `springSnappy` SHALL be a spring animation with 0.3s response and 0.8 damping fraction
- AND `springGentle` SHALL be a spring animation with 0.5s response and 0.7 damping fraction

---

### Requirement: Design System — CardStyle Modifier
The `CardStyle` view modifier SHALL apply consistent card styling to views.

#### Scenario: CardStyle application
- GIVEN a view has `.cardStyle()` applied
- THEN the view SHALL have 16pt padding
- AND a `Theme.surface` background with `RoundedRectangle` of `Theme.radiusMedium` corner radius

---

### Requirement: Design System — SectionHeader Modifier
The `SectionHeader` view modifier SHALL apply consistent section header styling to text.

#### Scenario: SectionHeader application
- GIVEN a view has `.sectionHeader()` applied
- THEN the text SHALL use caption font with semibold weight
- AND `Theme.textSecondary` foreground color
- AND uppercase text case transformation

---

### Requirement: Processing Overlay Component
`ProcessingOverlay` SHALL display a compact progress indicator during export operations.

#### Scenario: Processing overlay display
- GIVEN `ProcessingOverlay` is rendered with a progress value and message
- THEN it SHALL show a `ProgressView` bar tinted with `Theme.accent`
- AND a message text in caption font with `Theme.textSecondary`
- AND the entire component SHALL be wrapped in `CardStyle`
- AND constrained to a maximum width of 200pt

---

### Requirement: WYSIWYG Preview Pipeline
The editor SHALL provide a What You See Is What You Get preview by processing frames at preview resolution before displaying them.

#### Scenario: Preview generation triggers
- GIVEN the project has frames
- WHEN any of the following properties change: `quantizeColors`, `ditherAlgorithm`, `ditherStrength`, `speed`, `maxWidth`, `filterPreset`, `filterIntensity`
- THEN a debounced preview update SHALL be scheduled after 300ms
- AND any previously scheduled preview update SHALL be cancelled

#### Scenario: Preview resolution and sampling
- GIVEN a preview update runs
- WHEN frames are available
- THEN frames SHALL be resized to 240×240pt
- AND if more than 30 frames exist, 30 frames SHALL be sampled evenly from the full set
- AND the preview pipeline SHALL include: Resize, Speed (if ≠ 1.0), Filter (if active), and Quantize stages
- AND the dither stage SHALL NOT be included in preview (for performance)

#### Scenario: Preview frame selection
- GIVEN the editor renders the animated preview
- WHEN `project.previewFrames` is non-empty
- THEN the preview SHALL display `project.previewFrames` (processed)
- WHEN `project.previewFrames` is empty
- THEN the preview SHALL display `project.frames` (raw)

---

### Requirement: Safe Array Access
The app SHALL provide a safe subscript extension on `Array` to prevent out-of-bounds crashes.

#### Scenario: Safe subscript within bounds
- GIVEN an array with elements
- WHEN accessing an index within bounds
- THEN the element SHALL be returned as an optional wrapping the value

#### Scenario: Safe subscript out of bounds
- GIVEN an array with elements
- WHEN accessing an index outside bounds
- THEN `nil` SHALL be returned instead of crashing

---

### Requirement: Share Sheet Integration
The app SHALL use a UIKit wrapper (`ActivityView`) to present the system share sheet from SwiftUI.

#### Scenario: Present share sheet
- GIVEN the app needs to share a file
- WHEN `ActivityView` is presented with a URL
- THEN a `UIActivityViewController` SHALL be created with the URL as the activity item
- AND no custom application activities SHALL be included

---

### Requirement: Accessibility Support
The app SHALL provide accessibility labels and values on key interactive elements.

#### Scenario: Timeline accessibility
- GIVEN `TimeScrubber` is displayed
- THEN the element SHALL ignore child accessibility elements
- AND provide label "Timeline"
- AND value "{formatted current time} of {formatted total time}"

#### Scenario: Trim handle accessibility
- GIVEN `TrimView` is displayed
- THEN the start handle SHALL have label "Trim start" with formatted time value
- AND the end handle SHALL have label "Trim end" with formatted time value

#### Scenario: Speed slider accessibility
- GIVEN `ControlsBar` is displayed
- THEN the speed slider SHALL have label "Playback speed"
- AND value "{speed}x" formatted to one decimal place

#### Scenario: Preview frame accessibility
- GIVEN `AnimatedPreview` is displaying a frame
- THEN the accessibility label SHALL be "Preview, frame {current index + 1} of {total frame count}"