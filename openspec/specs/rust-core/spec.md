# Rust Core Specification

## Purpose

Describes the Rust FFI library (`fastgif-core`) that provides NeuQuant color quantization and GIF encoding to the iOS host application via a C ABI. The library accepts raw RGBA frame data, performs palette optimization per frame using the NeuQuant algorithm, and produces a single GIF byte buffer. It also defines the memory ownership contract across the FFI boundary and the cross-compilation build pipeline.

## Requirements

### Requirement: Crate Identity and Dependencies

The library SHALL be named `fastgif-core` and published as a static library (`staticlib` crate type). It SHALL depend on `color_quant` version 1.1 for NeuQuant color quantization and `gif` version 0.13 for GIF encoding. The release profile SHALL set `opt-level=3`, `lto=true`, `codegen-units=1`, and `strip=true` for maximum optimization and minimal binary size.

#### Scenario: Crate type configuration
- GIVEN the `Cargo.toml` manifest
- WHEN the crate is built
- THEN the `crate-type` SHALL be `["staticlib"]` to produce a static archive suitable for iOS linking

#### Scenario: Dependency versions
- GIVEN the crate's dependency declarations
- WHEN the build resolves dependencies
- THEN `color_quant` SHALL be version 1.1 and `gif` SHALL be version 0.13

#### Scenario: Release profile optimization
- GIVEN the `[profile.release]` section
- WHEN the crate is compiled in release mode
- THEN `opt-level` SHALL be 3, `lto` SHALL be true, `codegen-units` SHALL be 1, and `strip` SHALL be true

### Requirement: C Header Interface

The library SHALL expose a C header (`fastgif_core.h`) defining two structs and two functions. The `RawFrame` struct SHALL contain an `rgba` pointer (`const uint8_t *`), `width` (`uint32_t`), `height` (`uint32_t`), and `delay_cs` (`uint16_t`). The `GIFOutput` struct SHALL contain a `data` pointer (`uint8_t *`) and `len` (`size_t`). The header SHALL declare `fastgif_encode()` and `fastgif_free()` with C linkage guarded by `extern "C"` blocks.

#### Scenario: RawFrame struct layout
- GIVEN the `fastgif_core.h` header
- WHEN the host application defines a `RawFrame`
- THEN it SHALL contain fields `rgba` (const uint8_t pointer), `width` (uint32_t), `height` (uint32_t), and `delay_cs` (uint16_t)

#### Scenario: GIFOutput struct layout
- GIVEN the `fastgif_core.h` header
- WHEN the host application receives a `GIFOutput`
- THEN it SHALL contain fields `data` (uint8_t pointer) and `len` (size_t)

#### Scenario: C++ compatibility
- GIVEN a C++ compiler including the header
- WHEN the header is parsed
- THEN the function declarations SHALL be wrapped in `extern "C"` blocks to prevent name mangling

### Requirement: FFI Encoding Function

The `fastgif_encode()` function SHALL accept a pointer to an array of `RawFrame` structs, a frame count, a color count, a loop count, and a quality value. It SHALL return a heap-allocated `GIFOutput` pointer on success or `NULL` on any failure. The function SHALL validate that the frames pointer is non-null and the count is non-zero. It SHALL derive width and height from the first frame only.

#### Scenario: Null frames pointer
- GIVEN a null `frames_ptr`
- WHEN `fastgif_encode()` is called
- THEN it SHALL return `NULL`

#### Scenario: Zero frame count
- GIVEN a non-null `frames_ptr` with `count` equal to 0
- WHEN `fastgif_encode()` is called
- THEN it SHALL return `NULL`

#### Scenario: Deriving frame dimensions
- GIVEN a valid array of `RawFrame` structs with at least one frame
- WHEN `fastgif_encode()` initializes the GIF encoder
- THEN it SHALL use the `width` and `height` of the first frame as the GIF canvas dimensions

#### Scenario: Successful encoding returns GIFOutput
- GIVEN valid input that completes encoding without error
- WHEN `fastgif_encode()` finishes
- THEN it SHALL return a non-null `GIFOutput` pointer containing the encoded GIF bytes and their length

#### Scenario: Encoding error returns NULL
- GIVEN valid input frames but an internal `gif::EncodingError` occurs
- WHEN `fastgif_encode()` encounters the error
- THEN it SHALL discard partial results and return `NULL`

### Requirement: Color Count Clamping

The `fastgif_encode()` function SHALL clamp the `colors` parameter to the range 2–256 inclusive before using it as the NeuQuant palette size. Values below 2 SHALL be clamped to 2. Values above 256 SHALL be clamped to 256.

#### Scenario: Colors below minimum
- GIVEN a `colors` value of 0 or 1
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective palette size SHALL be 2

#### Scenario: Colors above maximum
- GIVEN a `colors` value greater than 256
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective palette size SHALL be 256

#### Scenario: Colors within range
- GIVEN a `colors` value between 2 and 256 inclusive
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective palette size SHALL be the provided value unchanged

### Requirement: Quality Parameter Clamping

The `fastgif_encode()` function SHALL clamp the `quality` parameter to the range 1–30 inclusive before using it as the NeuQuant sample factor. A value of 1 produces the highest quality (slowest). A value of 30 produces the fastest encoding (lowest quality).

#### Scenario: Quality below minimum
- GIVEN a `quality` value of 0 or negative
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective sample factor SHALL be 1

#### Scenario: Quality above maximum
- GIVEN a `quality` value greater than 30
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective sample factor SHALL be 30

#### Scenario: Quality within range
- GIVEN a `quality` value between 1 and 30 inclusive
- WHEN `fastgif_encode()` processes the parameter
- THEN the effective sample factor SHALL be the provided value unchanged

### Requirement: NeuQuant Per-Frame Palette Optimization

For each frame, the encoder SHALL create a new `NeuQuant` instance trained on that frame's RGBA pixel data. It SHALL use `color_map_rgb()` to extract the local palette as packed RGB triples and `index_of()` to map each pixel to its nearest palette index. The GIF encoder SHALL NOT use a global palette; each frame SHALL carry its own local palette.

#### Scenario: NeuQuant training per frame
- GIVEN a RawFrame with RGBA pixel data
- WHEN the encoder processes the frame
- THEN it SHALL instantiate `NeuQuant::new(sample_fac, num_colors, rgba)` which trains the neural network immediately on the frame's pixels

#### Scenario: Building the local palette
- GIVEN a trained NeuQuant instance for a frame
- WHEN the encoder builds the GIF frame palette
- THEN it SHALL call `color_map_rgb()` which returns RGB triples as `[r, g, b, r, g, b, ...]` suitable for the GIF palette field

#### Scenario: Mapping pixels to palette indices
- GIVEN a trained NeuQuant instance and the frame's RGBA pixel data
- WHEN the encoder builds the index buffer
- THEN it SHALL iterate each pixel as a 4-byte RGBA chunk, call `index_of()` to find the nearest palette entry, and collect results as `u8` indices

#### Scenario: No global palette
- GIVEN the GIF encoder initialization
- WHEN the encoder is created
- THEN it SHALL be initialized with an empty global palette (`&[]`) so that all palette information resides in per-frame local palettes

#### Scenario: Frame metadata propagation
- GIVEN a RawFrame with width, height, and delay_cs
- WHEN the encoder writes the GIF frame
- THEN the `gif::Frame` SHALL have `width` set to `rf.width`, `height` set to `rf.height`, `delay` set to `rf.delay_cs`, `palette` set to the NeuQuant-generated palette, and `buffer` set to the pixel index array

### Requirement: Loop Count Configuration

The `fastgif_encode()` function SHALL interpret a `loop_count` of 0 as infinite looping and any positive value as a finite loop count. It SHALL configure the GIF encoder's repeat setting accordingly before writing frames.

#### Scenario: Infinite looping
- GIVEN a `loop_count` of 0
- WHEN `fastgif_encode()` configures the encoder
- THEN it SHALL set `gif::Repeat::Infinite`

#### Scenario: Finite looping
- GIVEN a `loop_count` of N where N > 0
- WHEN `fastgif_encode()` configures the encoder
- THEN it SHALL set `gif::Repeat::Finite(N)`

### Requirement: Output Memory Ownership Transfer

On successful encoding, `fastgif_encode()` SHALL transfer ownership of the encoded byte buffer to the caller via `Box::into_raw()`. The returned `GIFOutput` SHALL be a heap-allocated struct containing a pointer to the data and its length. The caller SHALL be responsible for freeing the output via `fastgif_free()`.

#### Scenario: Heap allocation of GIFOutput
- GIVEN a successful encoding producing a byte buffer
- WHEN `fastgif_encode()` constructs the return value
- THEN it SHALL create a `GIFOutput` struct with the data pointer and length, box it, and transfer ownership via `Box::into_raw()`

#### Scenario: Buffer capacity pre-allocation
- GIVEN a frame count for the encoding operation
- WHEN `fastgif_encode()` initializes the output buffer
- THEN it SHALL pre-allocate `Vec::with_capacity(count * 4096)` bytes to reduce reallocations

#### Scenario: Ownership transfer via forget
- GIVEN the encoded byte buffer as a `Vec<u8>`
- WHEN `fastgif_encode()` prepares the data pointer
- THEN it SHALL convert the Vec to a `Box<[u8]>`, extract the raw pointer via `as_mut_ptr()`, call `std::mem::forget()` on the box to prevent deallocation, and store the pointer in `GIFOutput`

### Requirement: FFI Free Function

The `fastgif_free()` function SHALL accept a `GIFOutput` pointer and safely deallocate both the data buffer and the struct itself. It SHALL be a no-op when called with a null pointer. It SHALL reconstruct the `Box<GIFOutput>` and the `Vec<u8>` data buffer from raw parts to ensure correct deallocation. The function SHALL NOT be called more than once for the same pointer.

#### Scenario: Null pointer safety
- GIVEN a null `GIFOutput` pointer
- WHEN `fastgif_free()` is called
- THEN it SHALL do nothing and return without error

#### Scenario: Freeing a valid GIFOutput
- GIVEN a non-null `GIFOutput` pointer returned by `fastgif_encode()`
- WHEN `fastgif_free()` is called
- THEN it SHALL reconstruct the `Box<GIFOutput>` via `Box::from_raw()`, reconstruct the `Vec<u8>` data buffer via `Vec::from_raw_parts()` using the data pointer, length, and capacity (equal to length), and drop both

#### Scenario: Double-free prevention contract
- GIVEN a `GIFOutput` pointer that has already been freed
- WHEN `fastgif_free()` is called again on the same pointer
- THEN the behavior SHALL be undefined (use-after-free), as documented in the safety contract

### Requirement: Safety Contract for FFI Callers

The FFI functions SHALL define safety preconditions that callers MUST satisfy. For `fastgif_encode()`, the `frames_ptr` MUST point to `count` valid `RawFrame` structs for the duration of the call, and each `RawFrame.rgba` MUST point to `width * height * 4` bytes of RGBA pixel data. For `fastgif_free()`, the pointer MUST be one returned by `fastgif_encode()` or null, and MUST NOT be freed more than once.

#### Scenario: Valid frames pointer obligation
- GIVEN a caller invoking `fastgif_encode()`
- WHEN the frames pointer is passed
- THEN the caller MUST ensure the pointer and all embedded `rgba` pointers remain valid for the entire duration of the call

#### Scenario: Pixel data size obligation
- GIVEN a `RawFrame` with width W and height H
- WHEN the frame is passed to `fastgif_encode()`
- THEN the `rgba` pointer MUST point to at least `W * H * 4` bytes of readable memory

#### Scenario: Free function pointer provenance
- GIVEN a pointer passed to `fastgif_free()`
- WHEN the pointer is non-null
- THEN it MUST have been returned by a prior call to `fastgif_encode()` and not previously freed

### Requirement: Cross-Compilation Build Pipeline

The build script (`build-ios.sh`) SHALL compile the Rust library for two targets: `aarch64-apple-ios-sim` (iOS Simulator on Apple Silicon) and `aarch64-apple-ios` (iOS Device). It SHALL create an XCFramework combining both architectures using `xcodebuild -create-xcframework`, copy the C header to the output directory, and place all artifacts under `FastGIF/RustCore/`.

#### Scenario: Building for iOS Simulator
- GIVEN the build script is executed
- WHEN it compiles the simulator target
- THEN it SHALL run `cargo build --release --target aarch64-apple-ios-sim`

#### Scenario: Building for iOS Device
- GIVEN the build script is executed
- WHEN it compiles the device target
- THEN it SHALL run `cargo build --release --target aarch64-apple-ios`

#### Scenario: Library verification
- GIVEN the two cargo build commands have completed
- WHEN the script checks for output
- THEN it SHALL verify that both `target/aarch64-apple-ios-sim/release/libfastgif_core.a` and `target/aarch64-apple-ios/release/libfastgif_core.a` exist, and exit with an error if either is missing

#### Scenario: Header copying
- GIVEN the build script is executing
- WHEN it prepares the output directory
- THEN it SHALL copy `include/fastgif_core.h` to `FastGIF/FastGIF/RustCore/`

#### Scenario: XCFramework creation
- GIVEN both static libraries and headers are available
- WHEN the script creates the XCFramework
- THEN it SHALL run `xcodebuild -create-xcframework` with the simulator library, device library, and shared headers, outputting to `FastGIF/FastGIF/RustCore/FastGIFCore.xcframework`

#### Scenario: Clean rebuild
- GIVEN a previous XCFramework exists at the output path
- WHEN the script runs
- THEN it SHALL remove the previous `FastGIFCore.xcframework` directory before creating the new one

#### Scenario: Script error handling
- GIVEN the build script uses `set -euo pipefail`
- WHEN any command in the script fails
- THEN the script SHALL exit immediately with a non-zero status code