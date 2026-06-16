# Provisioning — Delta

## ADDED Requirements

### Requirement: Reference Fixture

The repository SHALL contain a deterministic reference clip `tests/fixtures/cat-loaf-3s.mov`
(synthetic 3-second gradient pan, 240×240, 24 fps) and its raw RGBA dump
`cat-loaf-3s-frames.bin`, generated reproducibly by `scripts/make-fixture.sh`. All quality
witnesses SHALL run against this fixture so results are comparable across commits and hosts.

#### Scenario: Fixture is reproducible
- GIVEN `scripts/make-fixture.sh`
- WHEN it is run on any host
- THEN it SHALL produce the identical `cat-loaf-3s.mov` and `cat-loaf-3s-frames.bin` bytes

### Requirement: Project-Owned Dev Simulator

The project SHALL own a named development simulator, created by
`scripts/sim-bootstrap.sh`, with its UDID recorded in `scripts/.sim-udid`. Build and test
scripts SHALL target this simulator so runs are reproducible and isolated from the user's
other simulators.

#### Scenario: Bootstrap creates and records the simulator
- GIVEN `scripts/sim-bootstrap.sh`
- WHEN it runs
- THEN it SHALL create the project simulator (if absent) and write its UDID to
  `scripts/.sim-udid`

### Requirement: Rust Build Pipeline

The Rust core SHALL be built into the iOS XCFramework via `rust/build-ios.sh`, producing
both `aarch64-apple-ios-sim` and `aarch64-apple-ios` slices and copying the C header. The
verification script SHALL invoke this build so the app always links the current Rust core.

#### Scenario: Both slices produced
- GIVEN `rust/build-ios.sh`
- WHEN it runs
- THEN it SHALL produce simulator and device static libraries and assemble
  `FastGIFCore.xcframework`

### Requirement: One-Command Verification

The repository SHALL provide `scripts/verify.sh` that, in one invocation: builds the Rust
core, runs `cargo test`, builds the app, runs the Swift test suite, and evaluates every
quality proposition (P1–P5 and the flicker gate). It SHALL exit non-zero if any
proposition fails, printing a per-proposition pass/fail summary.

#### Scenario: Single entry point reports all propositions
- GIVEN `scripts/verify.sh`
- WHEN it runs
- THEN it SHALL print a pass/fail line for each of P1–P5 and the flicker gate, and exit
  non-zero if any fails

#### Scenario: Harness detects the real defects before the fix
- GIVEN the pre-fix encoder (per-frame palettes, hardcoded colors)
- WHEN `verify.sh` runs
- THEN it SHALL FAIL the flicker gate and the preview-parity proposition, proving the
  harness actually detects the defects this change exists to fix

### Requirement: CI Quality Gate

The repository SHALL include a CI configuration template that runs `scripts/verify.sh` on
every change and blocks merge on failure. The gate SHALL treat the flicker regression bound
and P1–P5 as required checks.

#### Scenario: CI blocks on regression
- GIVEN a change that increases flicker above the bound for its commit stage
- WHEN CI runs `verify.sh`
- THEN the gate SHALL fail and block the merge
