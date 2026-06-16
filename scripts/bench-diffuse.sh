#!/usr/bin/env bash
# Records the row-tile diffusion speedup (task 5.4). Informational: prints the
# measured speedup of diffuse_tiled vs diffuse_sequential at a few sizes. The
# parallel diffuser is byte-identical to sequential (witnessed by P1 /
# tests/sierra_parity.rs); this just quantifies the wall-clock win.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$REPO/rust/fastgif-core"
TILES="${TILES:-8}"

cargo build --quiet --release --manifest-path "$CORE/Cargo.toml" --bin bench_diffuse || exit 1
BIN="$CORE/target/release/bench_diffuse"

# A few representative export sizes.
"$BIN" 480 480 72 "$TILES"
"$BIN" 720 720 48 "$TILES"
"$BIN" 1024 1024 24 "$TILES"
