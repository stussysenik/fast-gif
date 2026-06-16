# UI — Delta

## MODIFIED Requirements

### Requirement: Export View

The Export View SHALL present exactly four formats — GIF, APNG, MP4, MOV — with honest
labels. It SHALL NOT offer WebP or HEIC. Format labels SHALL NOT imply animation support
that the encoder does not deliver. The size/quality preview SHALL reflect the actual
color count and `Quality` preset that will be used for export.

#### Scenario: Honest format list
- GIVEN the Export View
- WHEN the format picker is shown
- THEN exactly GIF, APNG, MP4, and MOV SHALL be selectable, and no format SHALL claim
  animation support it cannot honor

### Requirement: Controls Bar

The Controls Bar SHALL expose Speed, Colors, and a `Quality` picker (`draft`/`good`/
`best`). It SHALL NOT expose the former dither-algorithm picker. The Colors selection
SHALL produce a visible change in the exported palette.

#### Scenario: Quality picker replaces dither picker
- GIVEN the Controls Bar
- WHEN it is displayed
- THEN it SHALL show a Quality picker with draft/good/best and SHALL NOT show
  Floyd–Steinberg / Ordered / Bayer algorithm options

#### Scenario: Colors selection is effective
- GIVEN a Colors value is changed
- WHEN the preview and export update
- THEN the resulting palette size SHALL change accordingly

### Requirement: Trim View

The Trim View handles SHALL remain fully within the track bounds at both extremes — a
handle at 0% or 100% SHALL NOT overflow the left or right edge, and handle height SHALL
NOT exceed the track. Dragging a handle SHALL live-preview the frame at that handle's
edge. Handles SHALL NOT cross, SHALL stop at a minimum gap (hard floor), and SHALL snap
to frame boundaries. Tap targets SHALL be at least 44pt.

#### Scenario: No edge overflow at extremes
- GIVEN the start handle at 0% and the end handle at 100%
- WHEN the trim bar is laid out
- THEN both handles SHALL be fully inside the track bounds horizontally and vertically

#### Scenario: Handle scrubs its own edge
- GIVEN the user drags the start (or end) handle
- WHEN the drag is in progress
- THEN the preview SHALL show the frame at the new start (or end) position

#### Scenario: Hard floor and no-cross
- GIVEN the user drags one handle toward the other
- WHEN they reach the minimum gap
- THEN the handles SHALL stop without crossing and SHALL NOT produce a zero-length range

### Requirement: Animated Preview Component

The Animated Preview SHALL restart its frame timer when frame CONTENT changes, not only
when frame count changes, so that re-quantization at equal frame count is reflected. When
a freshly computed exact frame settles, the component SHALL perform a sub-150ms
cross-dissolve from the previous exact frame to the new one (snap-to-truth).

#### Scenario: Content change restarts animation
- GIVEN the same number of frames but changed pixel content (e.g. new color count)
- WHEN the content updates
- THEN the animator SHALL refresh using the new frames and their delays

#### Scenario: Snap-to-truth on settle
- GIVEN a stale exact frame is displayed and a new exact frame finishes computing
- WHEN the new frame is applied
- THEN the component SHALL cross-dissolve from the previous exact frame to the new one in
  under 150ms

## ADDED Requirements

### Requirement: Honest Quality Surfacing

The UI SHALL NOT present any control whose selection does not change the output. Every
exposed encoding control (Colors, Quality, Speed, trim) SHALL have an observable effect
on the preview and the exported file.

#### Scenario: No placebo controls
- GIVEN any encoding control in the UI
- WHEN its value is changed
- THEN the change SHALL be observable in the preview and the exported output
