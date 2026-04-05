#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/fastgif-core"

echo "==> Building for iOS Simulator (aarch64-apple-ios-sim)..."
cargo build --release --target aarch64-apple-ios-sim

echo "==> Building for iOS Device (aarch64-apple-ios)..."
cargo build --release --target aarch64-apple-ios

SIM_LIB="target/aarch64-apple-ios-sim/release/libfastgif_core.a"
DEV_LIB="target/aarch64-apple-ios/release/libfastgif_core.a"

if [[ ! -f "$SIM_LIB" ]]; then
    echo "ERROR: Simulator library not found: $SIM_LIB" >&2
    exit 1
fi
if [[ ! -f "$DEV_LIB" ]]; then
    echo "ERROR: Device library not found: $DEV_LIB" >&2
    exit 1
fi

# Output directory inside the Xcode project
OUT_DIR="$SCRIPT_DIR/../FastGIF/FastGIF/RustCore"
mkdir -p "$OUT_DIR"

# Copy the C header
cp include/fastgif_core.h "$OUT_DIR/"

# Remove any previous xcframework before recreating
rm -rf "$OUT_DIR/FastGIFCore.xcframework"

echo "==> Creating XCFramework at $OUT_DIR/FastGIFCore.xcframework ..."
xcodebuild -create-xcframework \
    -library "$SIM_LIB" -headers include/ \
    -library "$DEV_LIB" -headers include/ \
    -output "$OUT_DIR/FastGIFCore.xcframework"

echo ""
echo "Done! XCFramework at: $OUT_DIR/FastGIFCore.xcframework"
