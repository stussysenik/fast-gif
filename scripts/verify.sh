#!/usr/bin/env bash
# One-command verification harness for FastGIF.
#
# Runs every proposition that can execute on the host (no simulator), reports
# pass/fail per proposition, and exits non-zero if any required gate fails.
#
# This is the gate referenced by the quality-verification + provisioning specs.
# It is RED by design until the quality work lands:
#   - C1 (now): P2 flicker gate fails — proves the harness detects the real
#     per-frame-palette defect. P1/P3/P4/P5 witnesses are reported as pending.
#   - C3/C4: global palette + temporal diffusion drive flicker under the gate.
#   - C5: row-tile parity witness (P1) lands.
#
# Flags (env):
#   ALPHA=0.3        flicker bound multiplier vs signed B0 (default: final C4 target)
#   COLORS=16        palette size the baseline was measured at
#   RUN_IOS=1        also run `flowdeck build` + `flowdeck test` (needs a booted sim)
#   SKIP_FIXTURE=1   reuse an existing fixture instead of regenerating
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

ALPHA="${ALPHA:-0.3}"
COLORS="${COLORS:-16}"
RUN_IOS="${RUN_IOS:-0}"
SKIP_FIXTURE="${SKIP_FIXTURE:-0}"

CORE="$REPO/rust/fastgif-core"
FIX_BIN="$REPO/tests/fixtures/cat-loaf-3s-frames.bin"
BASELINE="$REPO/tests/fixtures/flicker-baseline.txt"
GIF_OUT="$REPO/tests/fixtures/.out-c$COLORS.gif"

# --- result tracking ---
declare -a RESULTS
fail=0
record() { # status label detail
    RESULTS+=("$1|$2|$3")
    [[ "$1" == "FAIL" ]] && fail=1
    return 0
}
hr() { printf '%s\n' "----------------------------------------------------------------"; }
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

say "FastGIF verify  (alpha=$ALPHA, colors=$COLORS, ios=$RUN_IOS)"

# --- Stage 1: Rust build + unit/integration tests ---
say "[1/5] Rust core: build + test"
if cargo build --quiet --manifest-path "$CORE/Cargo.toml" 2>&1; then
    record PASS "rust-build" "cargo build"
else
    record FAIL "rust-build" "cargo build failed"
fi
# cargo test runs any present witnesses (sierra_parity=P1, sampling_sufficiency=P4, ...).
TEST_OUT="$(cargo test --quiet --manifest-path "$CORE/Cargo.toml" 2>&1)"; TEST_RC=$?
echo "$TEST_OUT"
if [[ $TEST_RC -eq 0 ]]; then
    record PASS "rust-test" "cargo test"
else
    record FAIL "rust-test" "cargo test failed"
fi

# --- Stage 2: fixture ---
say "[2/5] Reference fixture"
if [[ "$SKIP_FIXTURE" != "1" || ! -f "$FIX_BIN" ]]; then
    if ./scripts/make-fixture.sh >/dev/null 2>&1; then
        record PASS "fixture" "regenerated"
    else
        record FAIL "fixture" "make-fixture.sh failed"
    fi
else
    record PASS "fixture" "reused existing"
fi

# --- Stage 3: baseline integrity (tamper check on the signed B0) ---
say "[3/5] Baseline integrity"
if [[ -f "$BASELINE" ]]; then
    STORED_HASH="$(grep '^HASH=' "$BASELINE" | cut -d= -f2)"
    RECOMPUTED="$(grep '^B0=' "$BASELINE" | git hash-object --stdin)"
    if [[ -n "$STORED_HASH" && "$STORED_HASH" == "$RECOMPUTED" ]]; then
        record PASS "baseline-sig" "B0 signature valid"
    else
        record FAIL "baseline-sig" "signature mismatch (stored=$STORED_HASH recomputed=$RECOMPUTED)"
    fi
else
    record FAIL "baseline-sig" "missing $BASELINE"
fi

# --- Stage 4: P2 flicker gate (host encode → measure) ---
say "[4/5] P2 — flicker gate"
# From C3 on, GIF export routes through the global-palette path; the gate measures
# what actually ships. Set GLOBAL=0 to measure the legacy per-frame encoder.
GLOBAL_FLAG=""
[[ "${GLOBAL:-1}" == "1" ]] && GLOBAL_FLAG="--global"
if cargo run --quiet --manifest-path "$CORE/Cargo.toml" --bin encode_fixture -- \
        "$FIX_BIN" "$GIF_OUT" --colors "$COLORS" $GLOBAL_FLAG >/dev/null 2>&1; then
    if swift tests/validate_gif.swift "$GIF_OUT" \
            --expected-frames 24 --expected-duration 2.88 --alpha "$ALPHA"; then
        record PASS "P2-flicker" "flicker <= max($ALPHA*B0, 0.5)"
    else
        record FAIL "P2-flicker" "flicker exceeds bound (expected RED until C3/C4)"
    fi
else
    record FAIL "P2-flicker" "host encode failed"
fi

# Witnesses that land in later commits — surfaced, not silently skipped.
for w in "P1:rust/fastgif-core/tests/sierra_parity.rs:C5" "P3:FastGIF/FastGIFTests/PreviewParityTests.swift:C2" \
         "P4:rust/fastgif-core/tests/sampling_sufficiency.rs:C3" "P5:scripts/determinism.sh:C4"; do
    id="${w%%:*}"; rest="${w#*:}"; path="${rest%:*}"; commit="${rest##*:}"
    if [[ -e "$REPO/$path" ]]; then
        record PASS "$id-present" "$path exists"
    else
        record PEND "$id-pending" "lands in $commit ($path)"
    fi
done

# P5 — cross-arch determinism (runs the witness if both host arches are present).
if [[ -x "$REPO/scripts/determinism.sh" ]]; then
    DET_OUT="$(COLORS="$COLORS" "$REPO/scripts/determinism.sh" 2>&1)"; DET_RC=$?
    if [[ $DET_RC -eq 0 ]] && echo "$DET_OUT" | grep -q "PASS"; then
        record PASS "P5-determinism" "GIF bytes identical across arches"
    elif echo "$DET_OUT" | grep -q "skipping"; then
        record PEND "P5-determinism" "skipped (missing host arch target)"
    else
        record FAIL "P5-determinism" "output diverged across arches"
    fi
fi

# --- Stage 5: iOS build/test (optional; needs a booted sim) ---
say "[5/5] iOS build + test"
if [[ "$RUN_IOS" == "1" ]]; then
    if command -v flowdeck >/dev/null 2>&1; then
        if flowdeck build 2>&1 | tail -5; then record PASS "ios-build" "flowdeck build"; else record FAIL "ios-build" "flowdeck build failed"; fi
        if flowdeck test  2>&1 | tail -5; then record PASS "ios-test"  "flowdeck test";  else record FAIL "ios-test"  "flowdeck test failed";  fi
    else
        record FAIL "ios-build" "flowdeck not found"
    fi
else
    record PEND "ios" "skipped (set RUN_IOS=1 to enable)"
fi

# --- summary ---
say "Summary"; hr
for r in "${RESULTS[@]}"; do
    IFS='|' read -r st label detail <<< "$r"
    case "$st" in
        PASS) c="\033[32mPASS\033[0m" ;;
        FAIL) c="\033[31mFAIL\033[0m" ;;
        *)    c="\033[33mPEND\033[0m" ;;
    esac
    printf " %b  %-14s %s\n" "$c" "$label" "$detail"
done
hr
if [[ $fail -eq 1 ]]; then
    printf '\033[31mVERIFY: FAIL\033[0m\n'
    exit 1
fi
printf '\033[32mVERIFY: PASS\033[0m\n'
