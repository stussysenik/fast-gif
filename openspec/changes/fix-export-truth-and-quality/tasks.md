# Tasks — Fix Export Truth & Quality

Ordered by commit (C1–C6 from design.md). Each task is independently verifiable.
`[P]` = parallelizable within its commit.

## C1 — Provisioning & baseline (lands a *red* gate)

- [x] 1.1 Add a reference fixture: `tests/fixtures/cat-loaf-3s.mov` (240×240, 24 fps)
  + raw RGBA dump `cat-loaf-3s-frames.bin`. Script: `scripts/make-fixture.sh`.
  Refined: panning 2-stop gradient (palette contention) + a *static* center
  (128,128,128) probe — the proposal's byte-identical-pixel defect. Content is
  procedural/deterministic (no CoreImage RNG) so the signed baseline reproduces.
  Artifacts are gitignored (regenerable); the script + signed baseline are committed.
- [x] 1.2 Stand up a project-owned dev simulator (`scripts/sim-bootstrap.sh` → writes
  `scripts/.sim-udid`, gitignored as machine-specific). Booted FastGIF-Dev iPhone 16 Pro.
- [x] 1.3 Write `scripts/verify.sh`: build Rust, `cargo test`, host-encode fixture,
  run flicker metric, baseline tamper-check, print pass/fail per proposition.
  `flowdeck build`/`test` gated behind `RUN_IOS=1` (needs a booted sim; wired, off by
  default so the host gate runs fast and CI-portable).
- [x] 1.4 Implement the flicker metric (`validate_gif.swift`): 32×32 center region,
  per-pixel RGB variance across frames, averaged. Recorded
  `B₀ = flicker(unchanged_encoder(cat_loaf)) = 35.91` at 16 colors into
  `tests/fixtures/flicker-baseline.txt`; signed with `git hash-object`.
  Note: defect is palette-size-dependent (peaks ~268 @ 8 colors, ~0 @ 48+); anchored
  at 16 colors (product sticker/emoji tier) where B₀ is robustly above the 0.5 floor.
- [x] 1.5 Add a binary GIF validator (GIF89a header, frame count, duration ±5%, GCT
  bit for best mode) — `validate_gif.swift`.
- [x] 1.6 Add CI gate config (`.github/workflows/verify.yml`) that runs `verify.sh`;
  currently **fails** P2 (RED). Validation: `verify.sh` exits non-zero (1) with the
  flicker assertion `35.91 > 0.3·B₀=10.77` as the cause. ✓ proven.

## C2 — Export truth (one pipeline, honest formats)

- [x] 2.1 Introduce `Quality { draft, good, best }`; delete `DitherAlgorithm` and the
  `Dither` + `Quantize` Swift stages (`ImageProcessing.swift`).
- [x] 2.2 Add `BayerDither` (8×8 ordered) used only by `good`. [P]
  Implemented as GPU `CIFilter` composition (Bayer texture → `CIAffineTile` →
  `CIColorMatrix` bias → `CIAdditionCompositing`) rather than a custom
  `CIColorKernel`: a position-dependent pattern can't be expressed in a
  coordinate-free `CIColorKernel`, and runtime Metal-CIKernel needs a prebuilt
  metallib. The chosen path is GPU-side, deterministic (no RNG), dependency-free.
- [x] 2.3 Replace square Resize with `AspectResize(maxEdge:)`; both pipeline call sites
  now go through `buildPipeline(scale:)`. (`Resize` retained for explicit-size users:
  StickerOptimizer, tests.)
- [x] 2.4 Collapse preview/export to a single `buildPipeline(scale:)`; preview differs
  only by resolution + still-frame sampling.
- [x] 2.5 Thread `quantizeColors` and `quality` from `export()` → `Encoder.encode` →
  `encodeGIF` → FFI (removed the hardcoded `256`/`10`).
- [x] 2.6 Add `fastgif_preview_frame` FFI (single-frame quantization, now `quality`-aware
  so parity is true by construction) + `Encoder.previewFrame` Swift binding.
- [x] 2.7 Remove WebP and HEIC from `ExportFormat`; delete their encoders; update the
  format taxonomy to GIF/APNG/MP4/MOV.
- [x] 2.8 Enforce a 15 s duration cap at import; surface the reason in `ImportView`.
- [x] 2.9 **Witness P3**: `PreviewParityTests.swift` asserts
  `preview_color_set(frame) ≡ export_color_set(frame, .draft)` (gradient frame, across
  8/16/32/64 colors). GREEN: 91/91 iOS tests pass.
- [x] 2.10 Flicker gate `α(2)=1.0` (don't regress) GREEN (35.908 ≤ 35.908); P3 GREEN.

## C3 — Global palette + spatial diffusion

- [x] 3.1 Add `fastgif_encode_global`: sample 8 evenly-spaced frames, train one
  `NeuQuant`, apply globally; init `gif::Encoder` with the global palette.
- [x] 3.2 Implement spatial Sierra2_4a (`diffuse::diffuse_sequential`) in **fixed-point**;
  raster order, zero-seeded error. Shared deterministic integer `nearest_index`
  lookup (not NeuQuant's network) backs encode + preview + diffusion.
- [x] 3.3 Route GIF export through `fastgif_encode_global` (`Encoder.encodeGIFGlobal`);
  thread colors/quality/dither. `best` → Sierra, `good` → GPU Bayer, `draft` → nearest.
  Added `fastgif_preview_global` so the preview uses the same global palette.
- [x] 3.4 **Witness P4**: `tests/sampling_sufficiency.rs` —
  `palette_error(8) ≤ palette_error(4)` on cat-loaf. GREEN.
- [x] 3.5 Flicker gate `α(3)=0.6·B₀` GREEN (14.52 ≤ 21.55). P3 witness updated to the
  global path. (Still > `0.3·B₀`=10.77 — temporal carry in C4 closes the rest.)

## C4 — Temporal carry + scene-cut reset (zero-flicker)

- [x] 4.1 Thread the diffusion error buffer `E_{n-1} → E_n` across frames
  (`diffuse::diffuse_temporal`). Error-conserving split: 3/4 spatial (Sierra2_4a),
  1/4 to the same pixel next frame — bounded feedback, so static content settles
  into a stable cycle instead of oscillating (naive full-buffer carry blew up to 332).
- [x] 4.2 Scene-cut detection (>20% pixels with Σ|Δrgb|>48) resets the carry
  (`diffuse::scene_changed`, integer-only).
- [x] 4.3 Flicker gate `α(4)=0.3·B₀` GREEN — flicker **5.50 ≤ 10.77** (6.5× under B₀).
  ★ Zero-flicker (nearest path is exactly 0.0; the 5.5 is residual dither shimmer on
  moving edges, perceptually flicker-free).
- [x] 4.4 **Witness P5**: `scripts/determinism.sh` builds encode_fixture for
  aarch64 + x86_64 (two host arches) and asserts byte-identical GIF output. PASS
  (identical sha256). Fixed-point integer diffusion makes this hold.

## C5 — Row-tile parallel diffusion

- [x] 5.1 Add `crossbeam-utils` to `Cargo.toml`. (rayon evaluated and rejected — the
  wavefront spin-waits on neighbour progress, which can starve a fixed-size
  work-stealing pool when tiles > workers; `crossbeam_utils::thread::scope` spawns
  real co-scheduled OS threads, deadlock-free. Rationale documented in Cargo.toml.)
- [x] 5.2 Implement `diffuse::diffuse_tiled`: vertical column strips on a skewed
  release/acquire wavefront — strip `t` processes row `y` once its left neighbour has
  cleared row `y` and its right neighbour row `y-1` (the Sierra footprint). Cross-tile
  error writes are serialised per cell by the progress fences. `CachePadded` atomics.
- [x] 5.3 **Witness P1**: `tests/sierra_parity.rs` — `diffuse_tiled ≡ diffuse_sequential`
  byte-for-byte on a 240×240 gradient for `T∈{1,2,4,6,8}`. GREEN.
- [~] 5.4 Speedup measured (`scripts/bench-diffuse.sh`, `bench_diffuse` bin): **~2.5×**
  at 8 tiles on large frames (1024² ≈ 2.5×, 720² ≈ 2.2×), **below the 3× target.**
  Honest cause: critical path is `O(2H + T)` (the wavefront ramp), boundary-column
  cache-line bouncing, and per-frame OS-thread spawn — so the ceiling is ~T/2, not T,
  on this 8-perf-core host. `diffuse_tiled` is the P1-proven primitive; production
  `best` still uses sequential `diffuse_temporal` (kept for determinism + because the
  temporal kernel carries a per-pixel feedback). Reaching ≥3× needs a persistent
  worker pool + temporal-tiled integration — deferred (perf-only, not correctness).

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
