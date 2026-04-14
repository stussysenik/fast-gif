#!/usr/bin/env swift
// Standalone TDD harness for TimelineModel.
// Runs via `/usr/bin/swift tests/timeline_model_tdd.swift`.
// Once this passes, the `TimelineModel` struct below is extracted verbatim
// into `FastGIF/FastGIF/Features/Editor/TimelineModel.swift` (identical shape).
// This file is the single source of truth for the geometry/detent math during
// TDD; the extracted copy in the app target must stay byte-identical.

import Foundation
import CoreGraphics

// =============================================================================
// MARK: - TimelineGeometry
// =============================================================================

/// Pure value-type geometry layer for the timeline rail.
///
/// Bridges source time (seconds) to rail space (points) as a bijection.
/// In the base state the mapping is linear; an optional `Warp` deforms the
/// mapping locally when handles approach each other — without changing the
/// type's shape or the forward/inverse contract.
///
/// This type sits at the bottom of the "parental stack" derivation chain:
///
///     TimelineModel → TimelineGeometry → xPosition / seconds → Grab → drag
///
/// Each layer is a pure function of the one above it. Tests exercise every
/// invariant without spinning up SwiftUI, AVFoundation, or Timer machinery.
///
/// Forward and inverse are intentionally **unclamped**. Renderers clamp at
/// the call site; drag math extrapolates past the rail edges so predicted-
/// end translations still yield a signed frame delta. Round-trip holds
/// across positive and negative x values.
struct TimelineGeometry: Equatable, Sendable {

    /// Non-linear deformation of the time→x mapping centered on a focus
    /// window. Used to implement proximity-driven fisheye: when the three
    /// timeline handles (start, end, playhead) get within 0.5s of each
    /// other, a smooth warp magnifies the cluster so the user can dial
    /// frames apart without losing whole-timeline context.
    ///
    /// The warp is a **piecewise-affine three-segment map** with segment
    /// widths interpolated by `amount`:
    ///
    ///     [0, f₀] → [0, pre]      linear within each segment
    ///     [f₀, f₁] → [pre, pre+focus]
    ///     [f₁, T] → [pre+focus, W]
    ///
    /// At `amount = 0`, the segment widths match a linear mapping exactly.
    /// At `amount = 1`, the focus segment takes `scale × linear_focus_width`
    /// rail space (capped at 95% of the rail), and the remaining space is
    /// distributed between pre and post in proportion to their linear
    /// shares. Intermediate values blend linearly, which keeps the blended
    /// map piecewise-affine and its inverse closed-form.
    struct Warp: Equatable, Sendable {
        /// Focus window in source seconds. Normalized at construction so
        /// `lowerBound ≤ upperBound` and both land within `[0, duration]`.
        let focus: ClosedRange<TimeInterval>
        /// Focus magnification at `amount = 1`. Values `>= 1` meaningful;
        /// effective magnification is capped so pre and post segments
        /// retain at least ~5% of the rail.
        let scale: Double
        /// Blend factor in `[0, 1]`. `0` reduces to linear. Callers compute
        /// this via a smoothstep over minimum pairwise handle distance so
        /// engagement and release are continuous.
        let amount: Double

        init(focus: ClosedRange<TimeInterval>, scale: Double, amount: Double) {
            let low = max(0, min(focus.lowerBound, focus.upperBound))
            let high = max(low, focus.upperBound)
            self.focus = low...high
            self.scale = max(1, scale)
            self.amount = max(0, min(amount, 1))
        }
    }

    /// Total source duration in seconds. Non-negative.
    let duration: TimeInterval
    /// Optional warp. `nil` means linear mapping; same as `amount = 0`.
    let warp: Warp?

    init(duration: TimeInterval, warp: Warp? = nil) {
        self.duration = max(0, duration)
        self.warp = warp
    }

    /// Forward map: seconds → x (points on the rail). Unclamped.
    /// Falls back to linear when no warp is active or amount is zero.
    func xPosition(forSeconds t: TimeInterval, railWidth: CGFloat) -> CGFloat {
        guard duration > 0, railWidth > 0 else { return 0 }
        guard let widths = segmentWidths(for: warp, railWidth: railWidth) else {
            return CGFloat(t / duration) * railWidth
        }
        return forwardMap(t: t, widths: widths)
    }

    /// Inverse map: x (points) → seconds. Exact closed-form inverse of
    /// `xPosition(forSeconds:railWidth:)`. Unclamped.
    func seconds(forX x: CGFloat, railWidth: CGFloat) -> TimeInterval {
        guard duration > 0, railWidth > 0 else { return 0 }
        guard let widths = segmentWidths(for: warp, railWidth: railWidth) else {
            return Double(x / railWidth) * duration
        }
        return inverseMap(x: x, widths: widths)
    }

    // MARK: - Piecewise-affine warp math

    /// Resolved per-segment rail widths and focus time bounds. `nil` means
    /// "no warp, use the linear fast path". Computed once per forward or
    /// inverse call so both stay consistent.
    private struct SegmentWidths {
        let f0: TimeInterval   // focus lower bound, clamped to [0, duration]
        let f1: TimeInterval   // focus upper bound, clamped to [f0, duration]
        let pre: CGFloat       // rail points from x=0 to focus start
        let focus: CGFloat     // rail points spanning the focus window
        let post: CGFloat      // rail points from focus end to x=W
    }

    /// Build per-segment widths. Returns `nil` when the mapping collapses
    /// to linear (no warp, zero amount, or degenerate focus window).
    private func segmentWidths(for warp: Warp?, railWidth W: CGFloat) -> SegmentWidths? {
        guard let warp, warp.amount > 0 else { return nil }
        let T = duration
        let f0 = max(0, min(warp.focus.lowerBound, T))
        let f1 = max(f0, min(warp.focus.upperBound, T))
        let focusSpan = f1 - f0
        guard focusSpan > 0 else { return nil }

        // Segment widths at amount = 0 (linear) — these sum to W exactly.
        let linearPre = CGFloat(f0 / T) * W
        let linearFocus = CGFloat(focusSpan / T) * W
        let linearPost = CGFloat((T - f1) / T) * W

        // Segment widths at amount = 1 (fully warped). Focus takes
        // `scale × linear_focus`, capped so pre and post together retain
        // at least 5% of the rail. When the focus already covers the
        // full duration (linearOutside == 0) there's no space to steal
        // from, so warping becomes a no-op and we leave all widths linear.
        let linearOutside = linearPre + linearPost
        let warpedFocus: CGFloat
        let warpedPre: CGFloat
        let warpedPost: CGFloat
        if linearOutside > 0 {
            warpedFocus = min(CGFloat(warp.scale) * linearFocus, W * 0.95)
            let remaining = W - warpedFocus
            warpedPre = remaining * (linearPre / linearOutside)
            warpedPost = remaining * (linearPost / linearOutside)
        } else {
            warpedFocus = linearFocus
            warpedPre = 0
            warpedPost = 0
        }

        // Blend linear and warped segment widths by amount. Because each
        // side sums to W, the blended triple also sums to W for any α.
        let α = CGFloat(warp.amount)
        let pre = (1 - α) * linearPre + α * warpedPre
        let focus = (1 - α) * linearFocus + α * warpedFocus
        let post = (1 - α) * linearPost + α * warpedPost

        return SegmentWidths(f0: f0, f1: f1, pre: pre, focus: focus, post: post)
    }

    /// Forward piecewise-affine map using resolved segment widths.
    /// Unclamped: extrapolates with the focus-segment slope when pre or
    /// post segments degenerate (focus touches an endpoint).
    private func forwardMap(t: TimeInterval, widths: SegmentWidths) -> CGFloat {
        let f0 = widths.f0
        let f1 = widths.f1
        if t < f0 {
            if f0 <= 0 { return focusSlope(widths: widths) * CGFloat(t - f0) + widths.pre }
            return CGFloat(t / f0) * widths.pre
        } else if t <= f1 {
            let span = f1 - f0
            if span <= 0 { return widths.pre }
            return widths.pre + CGFloat((t - f0) / span) * widths.focus
        } else {
            let postSpan = duration - f1
            if postSpan <= 0 {
                return widths.pre + widths.focus + focusSlope(widths: widths) * CGFloat(t - f1)
            }
            return widths.pre + widths.focus + CGFloat((t - f1) / postSpan) * widths.post
        }
    }

    /// Inverse piecewise-affine map using resolved segment widths.
    /// Unclamped: extrapolates with the focus-segment slope when pre or
    /// post segments degenerate (focus touches an endpoint).
    private func inverseMap(x: CGFloat, widths: SegmentWidths) -> TimeInterval {
        let f0 = widths.f0
        let f1 = widths.f1
        let preEnd = widths.pre
        let focusEnd = widths.pre + widths.focus
        if x < preEnd {
            if widths.pre <= 0 {
                let slope = focusSlope(widths: widths)
                guard slope > 0 else { return f0 }
                return f0 + TimeInterval((x - preEnd) / slope)
            }
            return TimeInterval(x / widths.pre) * f0
        } else if x <= focusEnd {
            if widths.focus <= 0 { return f0 }
            let span = f1 - f0
            return f0 + TimeInterval((x - preEnd) / widths.focus) * span
        } else {
            if widths.post <= 0 {
                let slope = focusSlope(widths: widths)
                guard slope > 0 else { return f1 }
                return f1 + TimeInterval((x - focusEnd) / slope)
            }
            let postSpan = duration - f1
            return f1 + TimeInterval((x - focusEnd) / widths.post) * postSpan
        }
    }

    /// Rail points per second inside the focus segment. Used as the
    /// extrapolation slope when pre or post segments are degenerate.
    private func focusSlope(widths: SegmentWidths) -> CGFloat {
        let span = widths.f1 - widths.f0
        guard span > 0, widths.focus > 0 else { return 0 }
        return widths.focus / CGFloat(span)
    }
}

// =============================================================================
// MARK: - TimelineModel
// =============================================================================

/// Pure value-type model for the FastGIF editor timeline.
/// Frame-indexed trim + playhead state with detent tokens for haptic triggers.
/// The SwiftUI view is a thin projection; all math lives here so it's testable
/// without pulling in SwiftUI, AVFoundation, or the full project target.
struct TimelineModel: Equatable, Sendable {
    let totalFrames: Int
    let fps: Int

    private(set) var trimStartFrame: Int
    private(set) var trimEndFrame: Int
    private(set) var playheadFrame: Int

    // Sub-frame fractional offsets for ms-precision mode. Stored in [0, 1)
    // — fraction of the *current frame interval*. The integer frame above
    // is the source of truth for haptics and trim clamping; the fraction is
    // an add-on that ms-precision callers populate. Integer-only callers
    // never see it because the integer mutators always reset it to 0.
    private(set) var trimStartFraction: Double = 0
    private(set) var trimEndFraction: Double = 0
    private(set) var playheadFraction: Double = 0

    // Monotonic tokens — SwiftUI wires these to `.sensoryFeedback(..., trigger:)`.
    // Using `&+=` so wrap-around never crashes during very long sessions.
    private(set) var secondDetentToken: Int = 0
    private(set) var endpointDetentToken: Int = 0
    private(set) var trimCrossingToken: Int = 0
    private(set) var frameStepToken: Int = 0

    init(
        totalFrames: Int,
        fps: Int = 24,
        trimStartFrame: Int = 0,
        trimEndFrame: Int? = nil,
        playheadFrame: Int = 0
    ) {
        precondition(totalFrames >= 2, "Timeline requires at least 2 frames")
        precondition(fps > 0, "fps must be positive")
        let last = totalFrames - 1
        let start = max(0, min(trimStartFrame, last - 1))
        let end = min(last, max(trimEndFrame ?? last, start + 1))
        let head = max(0, min(playheadFrame, last))
        self.totalFrames = totalFrames
        self.fps = fps
        self.trimStartFrame = start
        self.trimEndFrame = end
        self.playheadFrame = head
    }

    // MARK: Derived

    var lastFrame: Int { totalFrames - 1 }
    var totalDuration: TimeInterval { Double(lastFrame) / Double(fps) }
    var trimStartSeconds: TimeInterval { Double(trimStartFrame) / Double(fps) }
    var trimEndSeconds: TimeInterval { Double(trimEndFrame) / Double(fps) }
    var playheadSeconds: TimeInterval { Double(playheadFrame) / Double(fps) }
    var trimmedDuration: TimeInterval { trimEndSeconds - trimStartSeconds }
    var playheadIsInTrim: Bool { playheadFrame >= trimStartFrame && playheadFrame <= trimEndFrame }

    /// Sub-frame precise time getters. `*Precise` getters fall through to the
    /// integer-frame values when no fraction has been set, so callers that
    /// don't care about ms mode get the same numbers as before.
    var playheadSecondsPrecise: TimeInterval { (Double(playheadFrame) + playheadFraction) / Double(fps) }
    var trimStartSecondsPrecise: TimeInterval { (Double(trimStartFrame) + trimStartFraction) / Double(fps) }
    var trimEndSecondsPrecise: TimeInterval { (Double(trimEndFrame) + trimEndFraction) / Double(fps) }

    // MARK: Mutations

    mutating func moveTrimStart(to target: Int) {
        let clamped = max(0, min(target, trimEndFrame - 1))
        guard clamped != trimStartFrame || trimStartFraction != 0 else { return }
        let oldSecond = secondFloor(trimStartFrame)
        let frameChanged = clamped != trimStartFrame
        trimStartFrame = clamped
        trimStartFraction = 0
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
            if clamped == 0 { endpointDetentToken &+= 1 }
        }
    }

    mutating func moveTrimEnd(to target: Int) {
        let clamped = max(trimStartFrame + 1, min(target, lastFrame))
        guard clamped != trimEndFrame || trimEndFraction != 0 else { return }
        let oldSecond = secondFloor(trimEndFrame)
        let frameChanged = clamped != trimEndFrame
        trimEndFrame = clamped
        trimEndFraction = 0
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
            if clamped == lastFrame { endpointDetentToken &+= 1 }
        }
    }

    mutating func movePlayhead(to target: Int) {
        let clamped = max(0, min(target, lastFrame))
        guard clamped != playheadFrame || playheadFraction != 0 else { return }
        let oldSecond = secondFloor(playheadFrame)
        let wasInTrim = playheadIsInTrim
        let frameChanged = clamped != playheadFrame
        playheadFrame = clamped
        playheadFraction = 0
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
            if clamped == 0 || clamped == lastFrame { endpointDetentToken &+= 1 }
            if wasInTrim != playheadIsInTrim { trimCrossingToken &+= 1 }
        }
    }

    // MARK: Sub-frame mutations (ms-precision mode)

    /// Move the playhead to a precise time in seconds. Snaps the integer
    /// frame DOWN (floor) and stores the residual as a sub-frame fraction.
    /// Haptics fire only when the integer frame crosses, so brushing
    /// through ms doesn't strobe the user.
    mutating func movePlayheadPrecise(toSeconds seconds: TimeInterval) {
        let clamped = max(0, min(seconds, totalDuration))
        let frameDouble = clamped * Double(fps)
        let frame = max(0, min(Int(frameDouble.rounded(.down)), lastFrame))
        let fraction = max(0, min(frameDouble - Double(frame), 0.999999))
        let frameChanged = frame != playheadFrame
        let fractionChanged = abs(fraction - playheadFraction) > 1e-12
        guard frameChanged || fractionChanged else { return }
        let oldSecond = secondFloor(playheadFrame)
        let wasInTrim = playheadIsInTrim
        playheadFrame = frame
        playheadFraction = fraction
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(frame) { secondDetentToken &+= 1 }
            if frame == 0 || frame == lastFrame { endpointDetentToken &+= 1 }
            if wasInTrim != playheadIsInTrim { trimCrossingToken &+= 1 }
        }
    }

    mutating func moveTrimStartPrecise(toSeconds seconds: TimeInterval) {
        let oneFrame = 1.0 / Double(fps)
        // Strictly less than trimEnd by at least one full frame so the model
        // invariant (start < end - 0) holds even with sub-frame fractions.
        let upperBound = trimEndSecondsPrecise - oneFrame
        let clamped = max(0, min(seconds, upperBound))
        let frameDouble = clamped * Double(fps)
        let frame = max(0, min(Int(frameDouble.rounded(.down)), trimEndFrame - 1))
        let fraction = max(0, min(frameDouble - Double(frame), 0.999999))
        let frameChanged = frame != trimStartFrame
        let fractionChanged = abs(fraction - trimStartFraction) > 1e-12
        guard frameChanged || fractionChanged else { return }
        let oldSecond = secondFloor(trimStartFrame)
        trimStartFrame = frame
        trimStartFraction = fraction
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(frame) { secondDetentToken &+= 1 }
            if frame == 0 { endpointDetentToken &+= 1 }
        }
    }

    /// Restore precise sub-frame state from raw seconds. Used by the model
    /// rebuild path (Timeline.refreshModel) to recover sub-frame state from
    /// the project's `Double` storage WITHOUT firing any haptic tokens.
    /// Integer frames are assumed already correct from `init`.
    mutating func restorePreciseFractions(
        playheadSeconds: TimeInterval,
        trimStartSeconds: TimeInterval,
        trimEndSeconds: TimeInterval
    ) {
        playheadFraction = clampFraction(playheadSeconds, integerFrame: playheadFrame)
        trimStartFraction = clampFraction(trimStartSeconds, integerFrame: trimStartFrame)
        trimEndFraction = clampFraction(trimEndSeconds, integerFrame: trimEndFrame)
    }

    private func clampFraction(_ seconds: TimeInterval, integerFrame: Int) -> Double {
        let frameDouble = max(0, seconds) * Double(fps)
        let residual = frameDouble - Double(integerFrame)
        return max(0, min(residual, 0.999999))
    }

    mutating func moveTrimEndPrecise(toSeconds seconds: TimeInterval) {
        let oneFrame = 1.0 / Double(fps)
        let lowerBound = trimStartSecondsPrecise + oneFrame
        let clamped = min(totalDuration, max(seconds, lowerBound))
        let frameDouble = clamped * Double(fps)
        let frame = max(trimStartFrame + 1, min(Int(frameDouble.rounded(.down)), lastFrame))
        let fraction = max(0, min(frameDouble - Double(frame), 0.999999))
        let frameChanged = frame != trimEndFrame
        let fractionChanged = abs(fraction - trimEndFraction) > 1e-12
        guard frameChanged || fractionChanged else { return }
        let oldSecond = secondFloor(trimEndFrame)
        trimEndFrame = frame
        trimEndFraction = fraction
        if frameChanged {
            frameStepToken &+= 1
            if oldSecond != secondFloor(frame) { secondDetentToken &+= 1 }
            if frame == lastFrame { endpointDetentToken &+= 1 }
        }
    }

    // MARK: Geometry

    /// Distance (in precise seconds) at which the fisheye warp fully
    /// engages. When any two handles get this close, `amount = 1`.
    static let warpEngageNearSeconds: TimeInterval = 0.2
    /// Distance at which engagement starts ramping up from zero.
    static let warpEngageFarSeconds: TimeInterval = 0.5
    /// Focus-segment magnification at `amount = 1`.
    static let warpScale: Double = 3.0
    /// Padding around the handle cluster used as the focus window.
    static let warpFocusPadSeconds: TimeInterval = 0.15

    /// Pure geometry derivation. Value type, recomputed on every access.
    /// Wraps `totalDuration` and an optional `Warp` derived from current
    /// trim/playhead positions. All rail-space math routes through this
    /// layer so forward and inverse mappings stay in lockstep, regardless
    /// of whether the warp is engaged.
    var geometry: TimelineGeometry {
        TimelineGeometry(duration: totalDuration, warp: computeWarp())
    }

    /// Trim-window width in precise seconds. This is what the fisheye
    /// engagement rule watches — playhead proximity is intentionally
    /// excluded so the default startup state (playhead sitting on the
    /// trim start) doesn't falsely trigger the warp.
    var trimWindowSeconds: TimeInterval {
        abs(trimEndSecondsPrecise - trimStartSecondsPrecise)
    }

    /// Minimum pairwise distance among the three handles in precise seconds.
    /// Exposed for debug surfaces — NOT used by engagement. See the comment
    /// on `trimWindowSeconds` for why.
    var minNeighborDeltaSeconds: TimeInterval {
        let s = trimStartSecondsPrecise
        let e = trimEndSecondsPrecise
        let h = playheadSecondsPrecise
        return min(abs(s - e), abs(s - h), abs(e - h))
    }

    /// Derive the warp state from the current trim window. Returns `nil`
    /// when the trim window is wider than `warpEngageFarSeconds`; otherwise
    /// returns a warp whose `amount` smoothsteps from 0 to 1 as the window
    /// tightens, centered on the trim region.
    private func computeWarp() -> TimelineGeometry.Warp? {
        let T = totalDuration
        guard T > 0 else { return nil }
        let window = trimWindowSeconds
        let near = Self.warpEngageNearSeconds
        let far = Self.warpEngageFarSeconds
        guard window < far else { return nil }

        let amount: Double
        if window <= near {
            amount = 1.0
        } else {
            let u = (far - window) / (far - near)
            amount = u * u * (3 - 2 * u)
        }

        let s = trimStartSecondsPrecise
        let e = trimEndSecondsPrecise
        let pad = Self.warpFocusPadSeconds
        let low = max(0, min(s, e) - pad)
        let high = min(T, max(s, e) + pad)
        guard low < high else { return nil }

        return TimelineGeometry.Warp(focus: low...high, scale: Self.warpScale, amount: amount)
    }

    /// Converts a drag translation (in points) to a signed frame delta.
    /// Rounded to nearest frame. Callers capture an anchor frame on first
    /// drag change, then call `anchor + frameDelta(...)` on each update.
    ///
    /// Delegates to `geometry.seconds(forX:)` so the formula stays identical
    /// under warped geometry — the inverse map handles local scale for us.
    func frameDelta(forPixelDelta dx: CGFloat, railWidth: CGFloat) -> Int {
        guard railWidth > 0, lastFrame > 0 else { return 0 }
        let deltaSeconds = geometry.seconds(forX: dx, railWidth: railWidth)
        return Int((deltaSeconds * Double(fps)).rounded())
    }

    /// x-coordinate (points) for a given frame on a rail of given width.
    /// Delegates to `geometry.xPosition(forSeconds:)`.
    func xPosition(for frame: Int, railWidth: CGFloat) -> CGFloat {
        guard lastFrame > 0 else { return 0 }
        let clamped = max(0, min(frame, lastFrame))
        let seconds = Double(clamped) / Double(fps)
        return geometry.xPosition(forSeconds: seconds, railWidth: railWidth)
    }

    // MARK: Private

    private func secondFloor(_ frame: Int) -> Int { frame / fps }
}

// =============================================================================
// MARK: - Standalone test harness
// =============================================================================

final class TestRunner {
    var passed = 0
    var failed = 0
    var failures: [String] = []

    func check(_ condition: Bool, _ msg: @autoclosure () -> String, file: StaticString = #file, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failed += 1
            failures.append("\(file):\(line) — \(msg())")
        }
    }

    func run(_ name: String, _ body: () -> Void) {
        let before = failed
        body()
        let delta = failed - before
        if delta == 0 {
            print("  ok  \(name)")
        } else {
            print("  FAIL \(name) (\(delta) failure\(delta == 1 ? "" : "s"))")
        }
    }

    func report() -> Int {
        print("")
        print("  \(passed) passed, \(failed) failed")
        if !failures.isEmpty {
            print("")
            print("FAILURES:")
            for f in failures { print("  • \(f)") }
        }
        return failed == 0 ? 0 : 1
    }
}

let t = TestRunner()

print("TimelineModel tests")
print("")

t.run("init clamps out-of-range values") {
    let m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: -10, trimEndFrame: 200, playheadFrame: 500)
    t.check(m.trimStartFrame == 0, "trimStartFrame should clamp to 0, got \(m.trimStartFrame)")
    t.check(m.trimEndFrame == 71, "trimEndFrame should clamp to 71, got \(m.trimEndFrame)")
    t.check(m.playheadFrame == 71, "playheadFrame should clamp to 71, got \(m.playheadFrame)")
}

t.run("moveTrimStart enforces minimum 1-frame gap to trimEnd") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 10, trimEndFrame: 11, playheadFrame: 0)
    m.moveTrimStart(to: 11)
    t.check(m.trimStartFrame == 10, "should clamp at trimEnd-1, got \(m.trimStartFrame)")
    m.moveTrimStart(to: 999)
    t.check(m.trimStartFrame == 10, "should still clamp at trimEnd-1")
}

t.run("moveTrimEnd enforces minimum 1-frame gap to trimStart") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 10, trimEndFrame: 11, playheadFrame: 0)
    m.moveTrimEnd(to: 10)
    t.check(m.trimEndFrame == 11, "should clamp at trimStart+1, got \(m.trimEndFrame)")
    m.moveTrimEnd(to: -5)
    t.check(m.trimEndFrame == 11, "should still clamp at trimStart+1")
}

t.run("movePlayhead clamps to [0, lastFrame]") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 0)
    m.movePlayhead(to: -50)
    t.check(m.playheadFrame == 0, "should clamp to 0, got \(m.playheadFrame)")
    m.movePlayhead(to: 500)
    t.check(m.playheadFrame == 71, "should clamp to 71, got \(m.playheadFrame)")
}

t.run("frameDelta converts pixel drag to frame offset") {
    let m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 0)
    // 72 frames => lastFrame=71 => on a 284pt rail, 284/71 = 4.0 pt/frame exactly.
    t.check(m.frameDelta(forPixelDelta: 0, railWidth: 284) == 0, "0px => 0 frames")
    t.check(m.frameDelta(forPixelDelta: 4, railWidth: 284) == 1, "4px => 1 frame, got \(m.frameDelta(forPixelDelta: 4, railWidth: 284))")
    t.check(m.frameDelta(forPixelDelta: 20, railWidth: 284) == 5, "20px => 5 frames, got \(m.frameDelta(forPixelDelta: 20, railWidth: 284))")
    t.check(m.frameDelta(forPixelDelta: -20, railWidth: 284) == -5, "-20px => -5 frames")
    t.check(m.frameDelta(forPixelDelta: 2, railWidth: 284) == 1, "2px (half-frame) => rounds to 1")
    t.check(m.frameDelta(forPixelDelta: 1.9, railWidth: 284) == 0, "1.9px (under half-frame) => rounds to 0")
}

t.run("xPosition places first and last frame at rail endpoints") {
    let m = TimelineModel(totalFrames: 49, fps: 24, trimStartFrame: 0, trimEndFrame: 48, playheadFrame: 0)
    let rail: CGFloat = 320
    t.check(abs(m.xPosition(for: 0, railWidth: rail) - 0) < 0.001, "frame 0 at x=0")
    t.check(abs(m.xPosition(for: 48, railWidth: rail) - 320) < 0.001, "frame 48 at x=320")
    let mid = m.xPosition(for: 24, railWidth: rail)
    t.check(abs(mid - 160) < 0.001, "frame 24 at midpoint, got \(mid)")
}

t.run("secondDetentToken fires when crossing whole-second boundary") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 23)
    let before = m.secondDetentToken
    m.movePlayhead(to: 24)  // Crosses 1.0s boundary (frame 24 at 24fps)
    t.check(m.secondDetentToken > before, "should fire at second boundary")
}

t.run("secondDetentToken does NOT fire within same second") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 5)
    let before = m.secondDetentToken
    m.movePlayhead(to: 10)  // Still in second 0 (frames 0..23)
    t.check(m.secondDetentToken == before, "should not fire within same second")
}

t.run("endpointDetentToken fires at frame 0 and lastFrame") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 10, trimEndFrame: 60, playheadFrame: 30)
    let start = m.endpointDetentToken
    m.movePlayhead(to: 0)
    t.check(m.endpointDetentToken == start + 1, "should fire at frame 0")
    m.movePlayhead(to: 71)
    t.check(m.endpointDetentToken == start + 2, "should fire at lastFrame (71)")
}

t.run("trimCrossingToken fires when playhead enters or exits trim region") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 20, trimEndFrame: 50, playheadFrame: 10)
    let before = m.trimCrossingToken
    m.movePlayhead(to: 25)  // enters
    t.check(m.trimCrossingToken == before + 1, "should fire on enter")
    m.movePlayhead(to: 60)  // exits
    t.check(m.trimCrossingToken == before + 2, "should fire on exit")
}

t.run("frameStepToken fires on every frame step") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 10)
    let before = m.frameStepToken
    m.movePlayhead(to: 11)
    m.movePlayhead(to: 12)
    m.movePlayhead(to: 13)
    t.check(m.frameStepToken == before + 3, "should step once per moved frame")
}

t.run("frameStepToken does NOT fire when target equals current") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 10)
    let before = m.frameStepToken
    m.movePlayhead(to: 10)  // No change
    t.check(m.frameStepToken == before, "should not fire when target equals current")
}

t.run("derived time values match frame positions at 24fps") {
    let m = TimelineModel(totalFrames: 73, fps: 24, trimStartFrame: 24, trimEndFrame: 48, playheadFrame: 36)
    t.check(abs(m.totalDuration - 3.0) < 1e-9, "72/24 = 3.0s, got \(m.totalDuration)")
    t.check(abs(m.trimStartSeconds - 1.0) < 1e-9, "24/24 = 1.0s")
    t.check(abs(m.trimEndSeconds - 2.0) < 1e-9, "48/24 = 2.0s")
    t.check(abs(m.playheadSeconds - 1.5) < 1e-9, "36/24 = 1.5s")
    t.check(abs(m.trimmedDuration - 1.0) < 1e-9, "trimmed = 2.0 - 1.0 = 1.0s")
}

t.run("playheadIsInTrim correctly bounds inclusive") {
    var m = TimelineModel(totalFrames: 72, fps: 24, trimStartFrame: 20, trimEndFrame: 50, playheadFrame: 19)
    t.check(!m.playheadIsInTrim, "frame 19 is outside")
    m.movePlayhead(to: 20)
    t.check(m.playheadIsInTrim, "frame 20 is inside (inclusive)")
    m.movePlayhead(to: 50)
    t.check(m.playheadIsInTrim, "frame 50 is inside (inclusive)")
    m.movePlayhead(to: 51)
    t.check(!m.playheadIsInTrim, "frame 51 is outside")
}

// =============================================================================
// MARK: - ms-precision (sub-frame) tests
// =============================================================================
// In ms-precision mode the playhead and trim handles can land BETWEEN frames.
// The model holds a fractional offset in addition to the integer frame, so all
// existing integer-frame math stays intact and tests above keep passing. Only
// the precise APIs and the precise getters change behavior.

t.run("playheadSecondsPrecise defaults to integer playheadSeconds when no fraction set") {
    let m = TimelineModel(totalFrames: 73, fps: 24, playheadFrame: 36)
    t.check(abs(m.playheadSecondsPrecise - 1.5) < 1e-9, "36/24 = 1.5s, got \(m.playheadSecondsPrecise)")
}

t.run("movePlayheadPrecise lands between frames at half-frame ms time") {
    // 24fps → frame interval = ~41.667ms → half-frame at ~20.833ms past frame 24 = 1.0208s
    var m = TimelineModel(totalFrames: 73, fps: 24, playheadFrame: 0)
    m.movePlayheadPrecise(toSeconds: 1.0 + (1.0 / 48.0))  // halfway between frames 24 and 25
    t.check(m.playheadFrame == 24, "snapped integer frame should be 24, got \(m.playheadFrame)")
    let expected = 1.0 + (1.0 / 48.0)
    t.check(abs(m.playheadSecondsPrecise - expected) < 1e-6,
            "precise seconds should retain sub-frame offset, got \(m.playheadSecondsPrecise) expected \(expected)")
}

t.run("movePlayheadPrecise still fires frameStepToken only when integer frame crosses") {
    var m = TimelineModel(totalFrames: 73, fps: 24, playheadFrame: 10)
    let before = m.frameStepToken
    // Move within the same integer frame → no haptic.
    m.movePlayheadPrecise(toSeconds: (10.0 / 24.0) + 0.001)
    t.check(m.frameStepToken == before, "no haptic for sub-frame movement")
    // Now cross to the next integer frame → one haptic.
    m.movePlayheadPrecise(toSeconds: (11.0 / 24.0) + 0.001)
    t.check(m.frameStepToken == before + 1, "one haptic when integer frame crosses, got \(m.frameStepToken - before)")
}

t.run("movePlayheadPrecise clamps to [0, totalDuration]") {
    var m = TimelineModel(totalFrames: 73, fps: 24, playheadFrame: 0)
    m.movePlayheadPrecise(toSeconds: -10)
    t.check(m.playheadFrame == 0, "negative seconds clamps to frame 0")
    t.check(m.playheadSecondsPrecise == 0, "and to 0 precise seconds")
    m.movePlayheadPrecise(toSeconds: 9999)
    t.check(m.playheadFrame == 72, "huge seconds clamps to lastFrame")
    t.check(abs(m.playheadSecondsPrecise - 3.0) < 1e-9, "and to totalDuration precise seconds")
}

t.run("moveTrimStartPrecise / moveTrimEndPrecise hold sub-frame seconds") {
    var m = TimelineModel(totalFrames: 121, fps: 30, trimStartFrame: 0, trimEndFrame: 120)
    // 30fps → frame interval = 33.333ms. Try 0.5167s = 15.5 frames worth.
    m.moveTrimStartPrecise(toSeconds: 15.5 / 30.0)
    t.check(m.trimStartFrame == 15, "integer start frame snaps DOWN to 15, got \(m.trimStartFrame)")
    t.check(abs(m.trimStartSecondsPrecise - 15.5/30.0) < 1e-9, "precise start retains 15.5/30")
    // End: 90.25 frames worth.
    m.moveTrimEndPrecise(toSeconds: 90.25 / 30.0)
    t.check(m.trimEndFrame == 90, "integer end frame snaps DOWN to 90, got \(m.trimEndFrame)")
    t.check(abs(m.trimEndSecondsPrecise - 90.25/30.0) < 1e-9, "precise end retains 90.25/30")
}

t.run("moveTrimStartPrecise enforces gap to trimEnd in seconds") {
    var m = TimelineModel(totalFrames: 121, fps: 30, trimStartFrame: 0, trimEndFrame: 60)
    // trimEnd is at 2.0s; try to move start past it.
    m.moveTrimStartPrecise(toSeconds: 2.5)
    // Must be strictly less than trimEndSecondsPrecise; allow fraction up to one frame below.
    t.check(m.trimStartSecondsPrecise < m.trimEndSecondsPrecise,
            "start must remain strictly less than end, got \(m.trimStartSecondsPrecise) vs \(m.trimEndSecondsPrecise)")
}

t.run("restorePreciseFractions populates fraction without firing haptic tokens") {
    var m = TimelineModel(totalFrames: 73, fps: 24, trimStartFrame: 24, trimEndFrame: 48, playheadFrame: 36)
    let frameToken = m.frameStepToken
    let secondToken = m.secondDetentToken
    let endToken = m.endpointDetentToken
    let crossToken = m.trimCrossingToken
    m.restorePreciseFractions(
        playheadSeconds: 1.5 + 0.005,
        trimStartSeconds: 1.0 + 0.0008,
        trimEndSeconds: 2.0 + 0.0023
    )
    t.check(m.frameStepToken == frameToken, "frameStepToken must not move on restore")
    t.check(m.secondDetentToken == secondToken, "secondDetentToken must not move on restore")
    t.check(m.endpointDetentToken == endToken, "endpointDetentToken must not move on restore")
    t.check(m.trimCrossingToken == crossToken, "trimCrossingToken must not move on restore")
    t.check(abs(m.playheadSecondsPrecise - (1.5 + 0.005)) < 1e-6, "playhead precise restored")
    t.check(abs(m.trimStartSecondsPrecise - (1.0 + 0.0008)) < 1e-6, "trimStart precise restored")
    t.check(abs(m.trimEndSecondsPrecise - (2.0 + 0.0023)) < 1e-6, "trimEnd precise restored")
}

t.run("integer mutators reset the playhead fraction so the two modes don't drift") {
    var m = TimelineModel(totalFrames: 73, fps: 24, playheadFrame: 0)
    m.movePlayheadPrecise(toSeconds: 1.5 + 0.01)  // sub-frame past 1.5s
    t.check(abs(m.playheadSecondsPrecise - (1.5 + 0.01)) < 1e-6, "precise stored")
    // Now use the integer API — should snap to that frame and clear the fraction.
    m.movePlayhead(to: 50)
    t.check(m.playheadFrame == 50, "integer move applied")
    t.check(abs(m.playheadSecondsPrecise - (50.0 / 24.0)) < 1e-9,
            "precise seconds should equal frame seconds after integer move, got \(m.playheadSecondsPrecise)")
}

// =============================================================================
// MARK: - TimelineGeometry tests (Slice 3)
// =============================================================================

t.run("TimelineGeometry xPosition maps 0s, midpoint, and full duration exactly") {
    let g = TimelineGeometry(duration: 3.0)
    t.check(abs(g.xPosition(forSeconds: 0.0, railWidth: 300) - 0)   < 1e-9, "0s → 0pt")
    t.check(abs(g.xPosition(forSeconds: 1.5, railWidth: 300) - 150) < 1e-9, "1.5s → 150pt")
    t.check(abs(g.xPosition(forSeconds: 3.0, railWidth: 300) - 300) < 1e-9, "3.0s → 300pt")
}

t.run("TimelineGeometry seconds(forX:) is the exact inverse of xPosition") {
    let g = TimelineGeometry(duration: 3.0)
    for x in stride(from: CGFloat(0), through: 300, by: 15) {
        let seconds = g.seconds(forX: x, railWidth: 300)
        let xBack = g.xPosition(forSeconds: seconds, railWidth: 300)
        t.check(abs(xBack - x) < 1e-9,
                "round-trip x=\(x) → s=\(seconds) → x=\(xBack)")
    }
}

t.run("TimelineGeometry is unclamped — negative x yields negative seconds") {
    let g = TimelineGeometry(duration: 3.0)
    t.check(abs(g.seconds(forX: -30, railWidth: 300) - (-0.3)) < 1e-9,
            "x=-30pt → -0.3s")
    t.check(abs(g.seconds(forX: 330, railWidth: 300) - 3.3) < 1e-9,
            "x=330pt → 3.3s (past end)")
}

t.run("TimelineGeometry handles zero-duration / zero-width without dividing by zero") {
    let zero = TimelineGeometry(duration: 0)
    t.check(zero.xPosition(forSeconds: 1.0, railWidth: 300) == 0, "zero duration → 0pt")
    t.check(zero.seconds(forX: 150, railWidth: 300) == 0, "zero duration → 0s")
    let normal = TimelineGeometry(duration: 3.0)
    t.check(normal.xPosition(forSeconds: 1.5, railWidth: 0) == 0, "zero rail → 0pt")
    t.check(normal.seconds(forX: 150, railWidth: 0) == 0, "zero rail → 0s")
}

t.run("TimelineModel.geometry exposes totalDuration without loss") {
    let m = TimelineModel(totalFrames: 73, fps: 24)
    t.check(abs(m.geometry.duration - m.totalDuration) < 1e-9,
            "geometry.duration must equal totalDuration, got \(m.geometry.duration) vs \(m.totalDuration)")
}

t.run("TimelineModel.xPosition delegation preserves the linear mapping") {
    let m = TimelineModel(totalFrames: 49, fps: 24)
    let rail: CGFloat = 320
    t.check(abs(m.xPosition(for: 0, railWidth: rail) - 0) < 1e-9, "frame 0 at x=0")
    t.check(abs(m.xPosition(for: 24, railWidth: rail) - 160) < 1e-9, "frame 24 at midpoint")
    t.check(abs(m.xPosition(for: 48, railWidth: rail) - 320) < 1e-9, "frame 48 at x=320")
}

t.run("TimelineModel.frameDelta delegation matches the original linear formula") {
    let m = TimelineModel(totalFrames: 72, fps: 24)
    // Same fixtures as the existing frameDelta test — this invariant pins
    // that the new inverse-based delegation produces identical frame deltas
    // for every case the linear formula covered, including negative drag.
    t.check(m.frameDelta(forPixelDelta: 0, railWidth: 284) == 0, "0px")
    t.check(m.frameDelta(forPixelDelta: 4, railWidth: 284) == 1, "4px = 1 frame")
    t.check(m.frameDelta(forPixelDelta: 20, railWidth: 284) == 5, "20px = 5 frames")
    t.check(m.frameDelta(forPixelDelta: -20, railWidth: 284) == -5, "-20px = -5 frames")
    t.check(m.frameDelta(forPixelDelta: 2, railWidth: 284) == 1, "2px rounds up")
    t.check(m.frameDelta(forPixelDelta: 1.9, railWidth: 284) == 0, "1.9px rounds down")
}

// =============================================================================
// MARK: - TimelineGeometry.Warp tests (Slice 4)
// =============================================================================

t.run("Slice 4: amount = 0 reduces warped geometry to exact linear") {
    let warp = TimelineGeometry.Warp(focus: 1.0...2.0, scale: 3.0, amount: 0)
    let warped = TimelineGeometry(duration: 5.0, warp: warp)
    let linear = TimelineGeometry(duration: 5.0)
    let rail: CGFloat = 500
    for s in stride(from: 0.0, through: 5.0, by: 0.25) {
        let wx = warped.xPosition(forSeconds: s, railWidth: rail)
        let lx = linear.xPosition(forSeconds: s, railWidth: rail)
        t.check(abs(wx - lx) < 1e-9, "amount=0 equals linear at t=\(s): got \(wx) vs \(lx)")
    }
}

t.run("Slice 4: fully-warped forward map is continuous and strictly monotonic") {
    let warp = TimelineGeometry.Warp(focus: 1.5...2.5, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 5.0, warp: warp)
    let rail: CGFloat = 1000
    var last: CGFloat = -.infinity
    for sInt in stride(from: 0, through: 500, by: 1) {
        let s = Double(sInt) / 100.0   // 0.00…5.00 at 0.01s resolution
        let x = g.xPosition(forSeconds: s, railWidth: rail)
        t.check(x > last, "monotonic at t=\(s): x=\(x) vs prior=\(last)")
        last = x
    }
}

t.run("Slice 4: fully-warped round-trip — seconds(forX: xPosition(forSeconds:)) ≈ identity") {
    let warp = TimelineGeometry.Warp(focus: 1.5...2.5, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 5.0, warp: warp)
    let rail: CGFloat = 1000
    for sInt in stride(from: 0, through: 500, by: 5) {
        let s = Double(sInt) / 100.0
        let x = g.xPosition(forSeconds: s, railWidth: rail)
        let back = g.seconds(forX: x, railWidth: rail)
        t.check(abs(back - s) < 1e-9, "round-trip at t=\(s) → x=\(x) → t=\(back)")
    }
}

t.run("Slice 4: blended round-trip — every amount in [0, 1] is an exact inverse") {
    let rail: CGFloat = 800
    for amount in stride(from: 0.0, through: 1.0, by: 0.1) {
        let warp = TimelineGeometry.Warp(focus: 2.0...3.0, scale: 3.0, amount: amount)
        let g = TimelineGeometry(duration: 10.0, warp: warp)
        for s in stride(from: 0.0, through: 10.0, by: 0.5) {
            let x = g.xPosition(forSeconds: s, railWidth: rail)
            let back = g.seconds(forX: x, railWidth: rail)
            t.check(abs(back - s) < 1e-9,
                    "blended round-trip failed: amount=\(amount) t=\(s) x=\(x) back=\(back)")
        }
    }
}

t.run("Slice 4: focus window magnifies relative to linear share") {
    let warp = TimelineGeometry.Warp(focus: 4.5...5.5, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 10.0, warp: warp)
    let rail: CGFloat = 1000
    // Linear share of a 1s focus on a 10s rail = 100pt. With scale=3 we
    // expect close to 300pt (capped at 95% of rail = 950pt, so not hit here).
    let x0 = g.xPosition(forSeconds: 4.5, railWidth: rail)
    let x1 = g.xPosition(forSeconds: 5.5, railWidth: rail)
    let focusWidth = x1 - x0
    t.check(focusWidth > 290 && focusWidth < 310,
            "focus width should be ~300pt (3× linear), got \(focusWidth)pt")
}

t.run("Slice 4: non-focus regions compress proportionally — total rail always W") {
    let warp = TimelineGeometry.Warp(focus: 4.5...5.5, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 10.0, warp: warp)
    let rail: CGFloat = 1000
    let x0 = g.xPosition(forSeconds: 0, railWidth: rail)
    let xEnd = g.xPosition(forSeconds: 10.0, railWidth: rail)
    t.check(abs(x0 - 0) < 1e-9, "t=0 at x=0")
    t.check(abs(xEnd - 1000) < 1e-9, "t=duration at x=W, got \(xEnd)")
}

t.run("Slice 4: focus at [0, duration] is a warp no-op (degenerate focus covers rail)") {
    let warp = TimelineGeometry.Warp(focus: 0...10.0, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 10.0, warp: warp)
    let linear = TimelineGeometry(duration: 10.0)
    let rail: CGFloat = 500
    for s in stride(from: 0.0, through: 10.0, by: 0.5) {
        let w = g.xPosition(forSeconds: s, railWidth: rail)
        let l = linear.xPosition(forSeconds: s, railWidth: rail)
        t.check(abs(w - l) < 1e-9, "full-coverage focus = linear at t=\(s)")
    }
}

t.run("Slice 4: focus touching the left edge (f0 = 0) still round-trips") {
    let warp = TimelineGeometry.Warp(focus: 0...1.0, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 5.0, warp: warp)
    let rail: CGFloat = 500
    for s in stride(from: 0.0, through: 5.0, by: 0.25) {
        let x = g.xPosition(forSeconds: s, railWidth: rail)
        let back = g.seconds(forX: x, railWidth: rail)
        t.check(abs(back - s) < 1e-9, "f0=0 round-trip at t=\(s) got \(back)")
    }
}

t.run("Slice 4: focus touching the right edge (f1 = duration) still round-trips") {
    let warp = TimelineGeometry.Warp(focus: 4.0...5.0, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 5.0, warp: warp)
    let rail: CGFloat = 500
    for s in stride(from: 0.0, through: 5.0, by: 0.25) {
        let x = g.xPosition(forSeconds: s, railWidth: rail)
        let back = g.seconds(forX: x, railWidth: rail)
        t.check(abs(back - s) < 1e-9, "f1=duration round-trip at t=\(s) got \(back)")
    }
}

t.run("Slice 4: warped inverse is unclamped — negative x gives negative seconds") {
    let warp = TimelineGeometry.Warp(focus: 2.0...3.0, scale: 3.0, amount: 1.0)
    let g = TimelineGeometry(duration: 5.0, warp: warp)
    let rail: CGFloat = 500
    let before = g.seconds(forX: -50, railWidth: rail)
    t.check(before < 0, "x=-50pt should give negative seconds, got \(before)")
    let after = g.seconds(forX: 550, railWidth: rail)
    t.check(after > 5.0, "x past rail should give seconds > duration, got \(after)")
}

t.run("Slice 4: model derives nil warp when trim window is wide") {
    // 10s @ 24fps, trim covers the whole duration — trim window = 10s.
    let m = TimelineModel(totalFrames: 241, fps: 24,
                          trimStartFrame: 0, trimEndFrame: 240, playheadFrame: 120)
    t.check(m.geometry.warp == nil, "no warp when trim window ≥ 0.5s")
}

t.run("Slice 4: model derives nil warp on default startup state (playhead on trim start)") {
    // Regression: original buggy rule engaged because min pairwise distance
    // was |start − head| = 0 when playhead defaulted to 0. Trim-only rule
    // ignores that false signal — trim window here is the full duration.
    let m = TimelineModel(totalFrames: 72, fps: 24)
    t.check(m.geometry.warp == nil, "default state → no warp")
}

t.run("Slice 4: model engages warp when trim window tightens to 0.375s") {
    // 10s @ 24fps. trimStart=100 (4.167s), trimEnd=109 (4.542s) → Δ = 0.375s.
    let m = TimelineModel(totalFrames: 241, fps: 24,
                          trimStartFrame: 100, trimEndFrame: 109, playheadFrame: 200)
    guard let warp = m.geometry.warp else {
        t.check(false, "warp should engage at 0.375s window")
        return
    }
    t.check(warp.amount > 0 && warp.amount < 1,
            "0.375s should ramp amount into (0, 1), got \(warp.amount)")
    t.check(warp.scale == TimelineModel.warpScale, "scale should be the model constant")
}

t.run("Slice 4: model pins warp amount to 1 at trim window ≤ 0.2s") {
    // 4 frames at 24fps ≈ 0.1667s < 0.2s.
    let m = TimelineModel(totalFrames: 241, fps: 24,
                          trimStartFrame: 100, trimEndFrame: 104, playheadFrame: 200)
    guard let warp = m.geometry.warp else {
        t.check(false, "warp should engage at 0.167s window")
        return
    }
    t.check(abs(warp.amount - 1.0) < 1e-9, "amount should be 1.0, got \(warp.amount)")
}

t.run("Slice 4: model's warp focus spans the trim window plus padding") {
    let m = TimelineModel(totalFrames: 241, fps: 24,
                          trimStartFrame: 100, trimEndFrame: 104, playheadFrame: 50)
    guard let warp = m.geometry.warp else {
        t.check(false, "warp should engage")
        return
    }
    let s = m.trimStartSecondsPrecise
    let e = m.trimEndSecondsPrecise
    t.check(warp.focus.lowerBound <= s, "focus low ≤ trim start, got \(warp.focus.lowerBound) vs \(s)")
    t.check(warp.focus.upperBound >= e, "focus high ≥ trim end, got \(warp.focus.upperBound) vs \(e)")
    // Padding is a model constant; focus should extend at least pad seconds
    // beyond each trim edge (unless clipped by [0, T]).
    let pad = TimelineModel.warpFocusPadSeconds
    t.check(warp.focus.lowerBound <= s - pad + 1e-9 || warp.focus.lowerBound == 0,
            "focus should pad by \(pad)s below start")
    t.check(warp.focus.upperBound >= e + pad - 1e-9 || warp.focus.upperBound == m.totalDuration,
            "focus should pad by \(pad)s above end")
}

t.run("Slice 4: regression — Slice 3 linear fixtures still pass under trim-only engagement") {
    // The Slice 3 frameDelta test uses a model with full-width trim and
    // playhead at 0; it needs warp to remain nil so the old linear
    // formula is exercised through delegation.
    let m = TimelineModel(totalFrames: 72, fps: 24,
                          trimStartFrame: 0, trimEndFrame: 71, playheadFrame: 0)
    t.check(m.geometry.warp == nil, "wide trim window → no warp")
    t.check(m.frameDelta(forPixelDelta: 4, railWidth: 284) == 1, "linear frameDelta")
    t.check(m.frameDelta(forPixelDelta: -20, railWidth: 284) == -5, "negative linear frameDelta")
    t.check(m.xPosition(for: 35, railWidth: 284) > 0, "linear xPosition")
}

exit(Int32(t.report()))
