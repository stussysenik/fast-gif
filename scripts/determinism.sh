#!/usr/bin/env bash
# Witness for proposition P5 (quality-verification capability):
#
#     output bytes identical across architectures for the fixture.
#
# The diffusion is fixed-point integer math precisely so that CI (which runs on
# one arch) proves something the user's device (a different arch) reproduces. We
# encode the fixture twice — once with an aarch64 binary, once with an x86_64
# binary (run under Rosetta on Apple Silicon) — and assert the GIF bytes match.
#
# "Two host arches" stands in for "simulator + device": both ship the same Rust
# core, and byte-identity across arches is the property that matters.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$REPO/rust/fastgif-core"
FIX="$REPO/tests/fixtures/cat-loaf-3s-frames.bin"
COLORS="${COLORS:-16}"

[[ -f "$FIX" ]] || "$REPO/scripts/make-fixture.sh" >/dev/null 2>&1

ARCHES=(aarch64-apple-darwin x86_64-apple-darwin)
OUTS=()
for arch in "${ARCHES[@]}"; do
    if ! rustup target list --installed | grep -q "^$arch$"; then
        echo "P5: target $arch not installed (rustup target add $arch); skipping" >&2
        exit 0
    fi
    echo "==> building encode_fixture for $arch" >&2
    if ! cargo build --quiet --release --manifest-path "$CORE/Cargo.toml" \
            --bin encode_fixture --target "$arch" 2>&1; then
        echo "P5: build failed for $arch" >&2
        exit 1
    fi
    out="$REPO/tests/fixtures/.det-$arch.gif"
    "$CORE/target/$arch/release/encode_fixture" "$FIX" "$out" --colors "$COLORS" --global \
        >/dev/null 2>&1 || { echo "P5: encode failed for $arch" >&2; exit 1; }
    OUTS+=("$out")
done

h0="$(shasum -a 256 "${OUTS[0]}" | cut -d' ' -f1)"
h1="$(shasum -a 256 "${OUTS[1]}" | cut -d' ' -f1)"
echo "P5: ${ARCHES[0]} = $h0" >&2
echo "P5: ${ARCHES[1]} = $h1" >&2
if [[ "$h0" == "$h1" ]]; then
    echo "P5: PASS — GIF bytes identical across arches" >&2
    exit 0
else
    echo "P5: FAIL — output diverged across arches (non-deterministic encode)" >&2
    exit 1
fi
