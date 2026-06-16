# Tasks — Fix Export Truth & Quality

Ordered by commit (C1–C6 from design.md). Each task is independently verifiable.
`[P]` = parallelizable within its commit.

## C1 — Provisioning & baseline (lands a *red* gate)

- [ ] 1.1 Add a reference fixture: `tests/fixtures/cat-loaf-3s.mov` (synthetic 3 s
  gradient-pan, 240×240, 24 fps) + raw RGBA dump `cat-loaf-3s-frames.bin`. Script:
  `scripts/make-fixture.sh`.
- [ ] 1.2 Stand up a project-owned dev simulator (`scripts/sim-bootstrap.sh` → writes
  `scripts/.sim-udid`). [P]
- [ ] 1.3 Write `scripts/verify.sh`: build Rust, `cargo test`, `flowdeck build`,
  `flowdeck test`, run flicker metric, print pass/fail per proposition. [P]
- [ ] 1.4 Implement the flicker metric (Swift or Rust): sample 32×32 center region
  across all frames, per-pixel RGB variance, averaged. Record
  `B₀ = flicker(unchanged_encoder(cat_loaf))` into `tests/fixtures/flicker-baseline.txt`;
  sign with `git hash-object`.
- [ ] 1.5 Add a binary GIF validator (asserts GIF89a header, frame count, loop block).
- [ ] 1.6 Add CI gate config (local template) that runs `verify.sh`; it MUST currently
  **fail** P2/P3 (proves the harness detects the real defects). Validation: `verify.sh`
  exits non-zero with the flicker assertion as the cause.

## C2 — Export truth (one pipeline, honest formats)

- [ ] 2.1 Introduce `Quality { draft, good, best }`; delete `DitherAlgorithm` and the
  `Dither` + `Quantize` Swift stages (`ImageProcessing.swift`).
- [ ] 2.2 Add `BayerDither` as an 8×8 Metal `CIColorKernel` used only by `good`. [P]
- [ ] 2.3 Replace square Resize with `AspectResize(maxEdge:)`; update both call sites.
- [ ] 2.4 Collapse preview/export to a single `buildPipeline(scale:)`; preview differs
  only by resolution + still-frame sampling.
- [ ] 2.5 Thread `quantizeColors` and `quality` from `export()` → `Encoder.encode` →
  `encodeGIF` → FFI (remove the hardcoded `256`/`10` at `Encoder.swift:87,89`).
- [ ] 2.6 Add `fastgif_preview_frame` FFI (single-frame quantization) + Swift binding.
- [ ] 2.7 Remove WebP and HEIC from `ExportFormat`; delete their encoders; update the
  format taxonomy to GIF/APNG/MP4/MOV.
- [ ] 2.8 Enforce a duration cap at import; surface the reason in `ImportView`.
- [ ] 2.9 **Witness P3**: `PreviewParityTests.swift` asserts
  `preview_color_set(frame) ≡ export_color_set(frame, .draft)` on cat-loaf frames.
- [ ] 2.10 Flicker gate `α(2)=1.0` (don't regress); P3 now GREEN.

## C3 — Global palette + spatial diffusion

- [ ] 3.1 Add `fastgif_encode_global`: sample 8 evenly-spaced frames, train one
  `NeuQuant`, apply globally; init `gif::Encoder` with the global palette.
- [ ] 3.2 Implement spatial Sierra2_4a (`diffuse::diffuse_sequential`) in **fixed-point**;
  raster order, zero-seeded error.
- [ ] 3.3 Route GIF export through `fastgif_encode_global`; thread colors/quality.
- [ ] 3.4 **Witness P4**: `tests/sampling_sufficiency.rs` —
  `palette_error(8) ≤ palette_error(4)` on cat-loaf.
- [ ] 3.5 Flicker gate `α(3)=0.6·B₀` (global palette cuts ≥40%) → GREEN.

## C4 — Temporal carry + scene-cut reset (zero-flicker)

- [ ] 4.1 Thread the diffusion error buffer `E_{n-1} → E_n` across frames.
- [ ] 4.2 Scene-cut detection (>20% pixel delta) resets the carry.
- [ ] 4.3 Flicker gate `α(4)=0.3·B₀` → GREEN. ★ Zero-flicker guarantee.
- [ ] 4.4 **Witness P5**: determinism — encode the fixture on simulator and on device
  (or two host arches); assert byte-identical GIF output.

## C5 — Row-tile parallel diffusion

- [ ] 5.1 Add `rayon`, `crossbeam-utils` to `Cargo.toml`.
- [ ] 5.2 Implement `diffuse::diffuse_tiled` with progress-tracking barriers (tile `t`
  waits for tile `t-1` to clear Sierra's 2-row footprint).
- [ ] 5.3 **Witness P1**: `tests/sierra_parity.rs` — `diffuse_tiled ≡ diffuse_sequential`
  byte-for-byte on a 240×240 gradient for `T∈{1,2,4,6,8}`.
- [ ] 5.4 Record encode wall-clock before/after on cat-loaf; assert speedup ≥ 3×.

## C6 — Preview coherence & UI hardening

- [ ] 6.1 Replace the preview debounce-only path with a monotonic **generation token**;
  discard any result whose token is stale (closes the race at `GIFProject.swift:106`).
- [ ] 6.2 Run the encode FFI on a background executor; add a cancellation flag +
  progress callback to `fastgif_encode_global`; abandon superseded requests.
- [ ] 6.3 Retain the last-exact frame; implement the sub-150 ms snap-to-truth
  cross-dissolve when a fresh exact frame settles.
- [ ] 6.4 Trim handles: contain within bounds at both extremes (no edge overflow),
  handle scrubs its own edge, frame-snap, hard floor / no-cross. (Builds on the interim
  containment already in `TrimView.swift`.)
- [ ] 6.5 Call `schedulePreview()` on `moveFrame`/`updateFrameDelay`; key the animator
  on a content version, not frame count.
- [ ] 6.6 Replace the Controls Bar dither picker with the Quality picker.

## Final

- [ ] F.1 `verify.sh` green end-to-end: P1–P5 all pass; flicker ≤ `0.3·B₀`.
- [ ] F.2 Confirm net Swift LOC ≤ pre-change (placebo deletions offset additions).
- [ ] F.3 `openspec validate fix-export-truth-and-quality --strict`.
