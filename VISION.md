# Vision

## Purpose

FastGIF exists to prove that a GIF creation app can be simultaneously:
- **The simplest** — three steps: Import → Adjust → Export
- **The highest quality** — GPU-accelerated encoding rivaling desktop tools
- **The most capable** — 6 export formats, batch processing, AI features, iMessage stickers

The loss function is singular: **how well does the app transform regular users into power users?** Not feature count. Not download numbers. User elevation.

## The Gap

The iOS GIF market in 2026 has a clear split:

**Discovery apps** (GIPHY) — massive libraries, no creation tools. You consume, not create.

**Basic editors** (ImgPlay, Momento) — decent editing, mediocre encoding. 256-color GIFs with visible banding. Aggressive paywalls ($10/mo for features that should be free).

**Quality encoders** (Gifski) — the gold standard for GIF quality, but macOS-only, video-only input, no editing, no batch processing.

**Nobody combines Gifski-quality encoding with ImgPlay-level editing on iOS.** That's the gap. FastGIF fills it in under 2,000 lines.

## Philosophy

### The iA Writer Principle

iA Writer succeeds because it removes decisions, not features. You open it and write. The typography is chosen for you. The focus mode exists but you discover it later. The app makes you better at writing by removing friction, not by adding tools.

FastGIF applies this principle to GIF creation:

1. **First 10 seconds** — Import a video, see it as frames, tap Export. Done.
2. **First 10 minutes** — Discover the speed slider, try a filter, change the export format.
3. **First hour** — Find the palette engine, experiment with dithering, batch-convert a folder.
4. **First week** — Build custom pipelines, export iMessage sticker packs, remove backgrounds.

Every feature exists. None is forced on you. The app teaches through progressive disclosure, not documentation.

### The Kernel Principle

> Every piece of software is a kernel.

The pipeline kernel — `Source → Decode → Process → Encode → Export` — is not just an implementation pattern. It's the product philosophy:

- **If a feature can't be expressed as a pipeline stage, it doesn't belong.** This keeps scope honest.
- **The kernel should be expressible in a single protocol.** If it takes more, the abstraction is wrong.
- **Modules are Lego blocks.** They snap onto the pipeline. They don't know about each other.

This constraint produces elegance by subtraction. The entire pipeline kernel is 66 lines. The entire app is 1,992 lines. Not because features were cut — because the architecture is honest.

## Target Users

### The Regular User (90%)
Opens the app to convert a video to a GIF. Wants it done in under 30 seconds. Doesn't know what dithering is. Will become a power user if the app teaches them without lecturing.

### The Creator (8%)
Makes GIFs for social media, Slack reactions, Discord emotes. Wants frame-level control, background removal, and one-tap export at platform-correct dimensions (Slack emoji = 128px/64KB).

### The Sticker Maker (2%)
Builds iMessage sticker packs. Needs to fit Apple's constraints (500KB APNG, 3 size tiers). Wants batch optimization and transparent export.

## Non-Goals

- **Not a GIF search engine.** GIPHY owns that. We don't compete on library size.
- **Not a social platform.** No profiles, no feeds, no followers.
- **Not a meme generator.** Text overlays are a feature, not the product.
- **Not subscription-first.** The core loop is free. Premium is for power features that justify their cost.

## Success Criteria

1. A first-time user creates and exports a GIF in under 30 seconds
2. The same user discovers a power feature within their first session
3. Export quality matches or exceeds Gifski on equivalent input
4. The entire codebase fits in one senior engineer's head (~2,000 LOC)
5. Zero external dependencies — ships with platform SDKs only
