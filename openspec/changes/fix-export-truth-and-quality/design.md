# Design — Fix Export Truth & Quality

## Context

This design is grounded in a verified interface review of the current code (file:line
citations below) and the product decisions resolved in the 2026-06-16 grill session.
The core architectural seam is fixed: **GPU/Core Image owns the interactive visual
layer; deterministic CPU-Rust owns the encode kernel.** Metal appears only where it
cannot affect the output bytes. No WebGPU (native iPhone app, no web surface).

## Current data flow (verified)

```
IMPORT   ImportView → project.importVideo() → Decoder.decodeVideo(maxDim:640) → [Frame]
EDIT     knob.didSet → schedulePreview() ──300ms debounce──► updatePreview()
              PREVIEW PIPELINE  { Resize(240×240) ; Speed? ; Filter? ; Quantize }   ← NO Dither, sampled ≤30
EXPORT   ExportView → project.export()
              EXPORT  PIPELINE  { Resize(maxW×maxW)? ; Speed? ; Filter? ; Quantize ; Dither }
              → Encoder.encode(format) → encodeGIF → fastgif_encode(colors=256 HARDCODED, quality=10)
                   → Rust: per-frame NeuQuant::new(); local palette; gif::Encoder::new(&[])
```

The three structural defects: **(1)** two different pipelines, **(2)** colors never
threaded, **(3)** per-frame palettes. This design unifies (1), wires (2), and replaces (3).

## Target data flow

```
buildPipeline(scale:) ── single source ─┬─► PREVIEW: run(scale: previewScale, sample: still-frame-at-playhead)
                                         └─► EXPORT : run(scale: export,       sample: all frames)
   stages: AspectResize ; Speed? ; Filter? ; (quantization+dither owned by Rust)

EXPORT → Encoder.encode(frames, format, colors, quality)
   GIF → fastgif_encode_global(frames, colors, quality, loop)   ← global palette + temporal Sierra
PREVIEW (still) → fastgif_preview_frame(frame, colors, quality) ← same quantizer, one frame
```

Both preview-still and export route through the **same NeuQuant + Sierra code path**,
guaranteeing parity (verified by the `quality-verification` capability).

## Key decisions

### D1 — Global palette, not per-frame (kills flicker)
Train one `NeuQuant` on 8 evenly-sampled frames (~1.8 MB at 240px; <100 ms on iPhone
16 Pro), then apply it to every frame. Rejected alternatives: `MPSImageHistogram`
(marginal distributions only — mathematically wrong); `libimagequant` (GPL,
incompatible with free App Store distribution). New FFI: `fastgif_encode_global`.

### D2 — Temporal Sierra2_4a diffusion with carry
Spatial Sierra2_4a first (commit 3), then thread the error buffer `E_{n-1} → E_n`
across frames (commit 4). Scene-cut detection (>20% pixel delta) resets the carry so
hard cuts don't smear. This is the step that takes flicker from "reduced" to "gone."

### D3 — Determinism is fixed-point, proven across targets
CI runs the simulator; users run arm devices. Float diffusion can round differently
across targets and silently break the byte-identity proof. Diffusion error
accumulation therefore uses **fixed-point integer math**, and a witness test asserts
identical output regardless of host. (Hardening gap #2 from the grill.)

### D4 — Row-tile parallel diffusion (rayon), bit-identical to sequential
Partition each frame into `T` horizontal tiles; tile `t` waits for tile `t-1` to clear
Sierra's 2-row footprint. Critical path `O(H + T·W)` vs `O(H·W)` → ~4–5× on a 6-core
device. Adds `rayon`, `crossbeam-utils`. Gated by a bit-identity witness: tiled output
MUST equal sequential output for `T ∈ {1,2,4,6,8}`.

### D5 — Quality preset replaces the dither placebo
`Quality { draft, good, best }`. `draft` = nearest-color, no diffusion; `good` = 8×8
Bayer (Metal `CIColorKernel`, GPU-side); `best` = temporal Sierra. The
`DitherAlgorithm` enum and the fake `Dither`/`Quantize` Swift stages are deleted.

### D6 — One pipeline, generation-token preview, snap-to-truth
`buildPipeline(scale:)` is the single definition; preview and export differ only in
resolution and frame-sampling. Preview is **always-exact** on the still frame at the
playhead — never an approximation, only (briefly) stale. A monotonic generation token
discards out-of-order results (closes the race at `GIFProject.swift:106`). When the
fresh exact frame lands, a sub-150 ms cross-dissolve ("snap-to-truth") swaps stale→exact
— the one signature GPU moment that signals speed without lying. Requires retaining the
last-exact frame as state. (Hardening gaps #1, #5.)

### D7 — Cancellation across the FFI
The encode FFI runs on a background executor (not the `@MainActor` class's resumed
thread) and accepts a cancellation flag + progress callback so a superseded
preview/export can be abandoned. Stages also check cancellation inside per-frame loops,
not only between stages.

### D8 — Aspect-correct Resize + duration cap
`AspectResize(maxEdge:)` fits the long edge and derives the other dimension from the
source aspect. Import enforces a hard duration cap (frame-array RAM model; unlimited is
v1.1) and surfaces the reason to the user. (Hardening gap #3.)

## Sequencing (maps to tasks.md)

```
C1 Provision + baseline   → fixtures, sim, verify.sh, flicker B₀ signed, CI gate (red)
C2 Export truth           → one pipeline, wire colors, AspectResize, Quality enum + Bayer,
                            drop WebP/HEIC, preview FFI + parity witness, duration cap
C3 Global palette         → fastgif_encode_global + spatial Sierra; flicker α(3)=0.6·B₀
C4 Temporal carry         → cross-frame error + scene-cut reset; flicker α(4)=0.3·B₀  ★zero-flicker
C5 Row-tile parallel      → rayon diffuse_tiled; bit-identity witness; speed
C6 UI hardening           → generation token, FFI cancellation, snap-to-truth, trim edge containment
```

## Verification propositions (executable; see quality-verification capability)

| ID | Assertion | Witness |
|---|---|---|
| P1 | `diffuse_tiled ≡ diffuse_sequential` byte-for-byte, `T∈{1,2,4,6,8}` | `tests/sierra_parity.rs` |
| P2 | `flicker(commit N) ≤ max(α(N)·B₀, 0.5)` | flicker metric + signed `B₀` |
| P3 | `preview_color_set(frame) ≡ export_color_set(frame, .draft)` | `PreviewParityTests.swift` |
| P4 | `palette_error(8 samples) ≤ palette_error(4 samples)` | `tests/sampling_sufficiency.rs` |
| P5 | output bytes identical on simulator and device for the fixture | determinism witness |

## Open questions

- Exact duration cap value (proposed ~10–15 s at chosen fps) — confirm before C2.
- Whether `draft`/`good` previews also need the still-frame exact path or can reuse
  the Bayer GPU preview (likely fine; `best` must use the exact Rust path).
