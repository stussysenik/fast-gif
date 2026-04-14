import Foundation
import CoreGraphics

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
    /// Unclamped: extrapolates with the pre-segment slope for `t < 0`
    /// and the post-segment slope for `t > duration`.
    private func forwardMap(t: TimeInterval, widths: SegmentWidths) -> CGFloat {
        let f0 = widths.f0
        let f1 = widths.f1
        if t < f0 {
            // Pre segment. When f0 == 0 the segment has zero extent and
            // we extrapolate through the focus segment's slope from t = 0.
            if f0 <= 0 { return focusSlope(widths: widths) * CGFloat(t - f0) + widths.pre }
            return CGFloat(t / f0) * widths.pre
        } else if t <= f1 {
            let span = f1 - f0
            if span <= 0 { return widths.pre }
            return widths.pre + CGFloat((t - f0) / span) * widths.focus
        } else {
            let postSpan = duration - f1
            if postSpan <= 0 {
                // f1 == duration: extrapolate using focus slope past the end.
                return widths.pre + widths.focus + focusSlope(widths: widths) * CGFloat(t - f1)
            }
            return widths.pre + widths.focus + CGFloat((t - f1) / postSpan) * widths.post
        }
    }

    /// Inverse piecewise-affine map using resolved segment widths.
    /// Unclamped: extrapolates with the pre-segment slope for `x < 0`
    /// and the post-segment slope for `x > railWidth`.
    private func inverseMap(x: CGFloat, widths: SegmentWidths) -> TimeInterval {
        let f0 = widths.f0
        let f1 = widths.f1
        let preEnd = widths.pre
        let focusEnd = widths.pre + widths.focus
        if x < preEnd {
            if widths.pre <= 0 {
                // Degenerate pre: extrapolate using focus slope.
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
    /// extrapolation slope when pre or post segments are degenerate
    /// (focus touches an endpoint), so the map stays continuous.
    private func focusSlope(widths: SegmentWidths) -> CGFloat {
        let span = widths.f1 - widths.f0
        guard span > 0, widths.focus > 0 else { return 0 }
        return widths.focus / CGFloat(span)
    }
}
