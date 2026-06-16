# Fix Export Truth & Quality

## Why

FastGIF's exports do not match what the UI promises, and the quality gap that
defines the product (flicker-free GIFs) is unimplemented. These are **measured**,
not suspected:

- **Per-frame palette flicker is real.** A pixel that is byte-identical
  `(128,128,128)` across 8 input frames exports as **5 distinct colors**
  (measured against the live `fastgif_encode`). The encoder trains a fresh
  `NeuQuant` per frame with no global palette (`rust/fastgif-core/src/lib.rs:65,81`).
- **The Colors picker is inert.** The GIF palette size is hardcoded to `256`
  at the FFI call (`Encoder.swift:87`); the 16/32/64/128 choices never reach Rust.
- **The Dither dropdown is a placebo.** Floyd–Steinberg / Ordered / Bayer all run
  the *same* `CIRandomGenerator` noise — there is no branch on the algorithm
  (`ImageProcessing.swift:106-126`) — and dithering is absent from the preview entirely.
- **Preview ≠ export.** Preview omits the Dither stage, hardcodes `Resize(240×240)`,
  and samples ≤30 frames; export uses `Resize(maxWidth×maxWidth)` and all frames
  (`GIFProject.swift:94-103` vs `49-63`). What the user sees animating is never the
  bytes that ship.
- **Resize distorts non-square clips.** Both paths pass `CGSize(maxWidth, maxWidth)`,
  forcing a square (`GIFProject.swift:52,95`).
- **WebP/HEIC silently drop every frame but the first** (`Encoder.swift:208-227`).
- **No cancellation across the FFI.** `fastgif_encode` is one synchronous blocking
  call (`Encoder.swift:83`); the preview path debounces but uses no generation token,
  leaving a race where a slow older task can overwrite a newer result
  (`GIFProject.swift:66-106`).
- **There is no proof of any of this.** There is no `rust/fastgif-core/tests/`
  directory; `cargo test` runs **0 tests**. The "verification" the spec describes
  does not exist.

This change closes all of the above and stands up the quality-verification and
provisioning machinery so the fixes are *proven*, deterministic, and repeatable.

## What Changes

1. **Honest exports** — wire the Colors picker to the GIF palette; make the dither
   choice real or remove it; fix Resize to preserve aspect ratio; remove WebP/HEIC
   (they cannot honestly carry an animation today). One pipeline feeds both preview
   and export so they are byte-equivalent at matched resolution.
2. **Zero-flicker quality** — replace per-frame palettes with one global palette
   trained on sampled frames, plus temporal Sierra2_4a error diffusion that carries
   error across frames, with scene-cut reset. Deterministic (fixed-point) so output
   is byte-identical on simulator and device.
3. **Quality preset** — collapse the meaningless dither algorithm picker into a
   `Quality { draft, good, best }` enum; `good` adds a real GPU 8×8 Bayer dither.
4. **Always-exact, cancellable preview** — generation-token coherence (no stale
   writes), cancellation across the FFI, a "snap-to-truth" cross-dissolve when the
   exact frame settles, and a duration cap enforced at import.
5. **Quality verification (new capability)** — flicker metric + signed baseline with
   a monotonic-decrease gate, row-tile diffusion bit-identity, sampling sufficiency,
   preview↔export parity, a binary GIF validator, and a sim-vs-device determinism check.
6. **Provisioning (new capability)** — a project-owned dev simulator, a reference
   fixture clip, the Rust build pipeline, a one-command `verify.sh`, and a CI gate.

## Capabilities Affected

| Capability | Type | Summary |
|---|---|---|
| `encoding` | MODIFIED + REMOVED | 4 honest formats; colors/quality threaded; WebP/HEIC removed |
| `rust-core` | MODIFIED + ADDED + REMOVED | global palette + temporal diffusion; preview FFI; deterministic; cancellable; rayon |
| `processing` | MODIFIED + ADDED + REMOVED | aspect-correct Resize; Quality preset + real Bayer; fake Dither/Quantize removed |
| `kernel` | MODIFIED + ADDED | one shared pipeline; generation-token preview; FFI cancellation; duration cap |
| `ui` | MODIFIED + ADDED | Quality picker; honest format list; trim edge containment + snap; snap-to-truth |
| `quality-verification` | ADDED (new) | flicker/parity/determinism propositions + executable witnesses |
| `provisioning` | ADDED (new) | dev simulator, fixtures, build pipeline, verify.sh, CI gate |

## Out of Scope

- GPU compute **inside** the encode kernel (Metal nearest-palette lookup) — deferred
  to v1.1; CI-invisible and risks the byte-identity guarantee. GPU stays on the
  visual/interactive layer only.
- Unlimited duration / streaming pipeline — deferred to v1.1; this change keeps the
  frame-array model and adds a hard duration cap instead.
- macOS / Catalyst; Giphy/Tenor browsers; undo/redo & onion-skinning.
- Root navigation redesign (single-canvas + overflow menu) — tracked separately;
  this change touches only the editor, controls, export, and trim surfaces.

## Impact / Risks

- **Determinism is load-bearing.** The whole verification story rests on
  byte-identical output across targets. If the diffusion uses non-deterministic
  floats, CI (simulator) will prove something the device doesn't reproduce. Mitigation:
  fixed-point diffusion + an explicit sim-vs-device determinism witness.
- **Behavior change is visible.** Removing WebP/HEIC and the dither algorithm names
  changes the UI; the Colors picker will now actually change output size/quality.
- **Net LOC should be ~flat or negative** — deleting placebo stages offsets new code.
