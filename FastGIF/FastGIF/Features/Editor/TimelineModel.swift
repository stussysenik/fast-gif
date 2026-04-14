import Foundation
import CoreGraphics

/// Pure value-type model for the FastGIF editor timeline.
/// Frame-indexed trim + playhead state with detent tokens for haptic triggers.
/// The SwiftUI view (`Timeline`) is a thin projection; all math lives here so
/// it can be exercised without SwiftUI, AVFoundation, or the full project target.
///
/// Detent tokens are monotonic counters. Bind them to `.sensoryFeedback(_:trigger:)`
/// in the view layer so each meaningful step (frame, second, endpoint, trim
/// crossing) fires a haptic when the token value changes.
struct TimelineModel: Equatable, Sendable {
    let totalFrames: Int
    let fps: Int

    private(set) var trimStartFrame: Int
    private(set) var trimEndFrame: Int
    private(set) var playheadFrame: Int

    /// Sub-frame fractional offsets for ms-precision mode. Stored in [0, 1)
    /// — fraction of the *current frame interval*. The integer frame above
    /// is the source of truth for haptics and trim clamping; the fraction is
    /// an add-on that ms-precision callers populate. Integer-only callers
    /// never see it because the integer mutators always reset it to 0.
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

    // MARK: - Derived

    var lastFrame: Int { totalFrames - 1 }
    var totalDuration: TimeInterval { Double(lastFrame) / Double(fps) }
    var trimStartSeconds: TimeInterval { Double(trimStartFrame) / Double(fps) }
    var trimEndSeconds: TimeInterval { Double(trimEndFrame) / Double(fps) }
    var playheadSeconds: TimeInterval { Double(playheadFrame) / Double(fps) }
    var trimmedDuration: TimeInterval { trimEndSeconds - trimStartSeconds }
    var playheadIsInTrim: Bool { playheadFrame >= trimStartFrame && playheadFrame <= trimEndFrame }

    /// Sub-frame precise time getters. Fall through to the integer-frame
    /// values when no fraction has been set, so callers that don't care
    /// about ms mode get the same numbers as before.
    var playheadSecondsPrecise: TimeInterval { (Double(playheadFrame) + playheadFraction) / Double(fps) }
    var trimStartSecondsPrecise: TimeInterval { (Double(trimStartFrame) + trimStartFraction) / Double(fps) }
    var trimEndSecondsPrecise: TimeInterval { (Double(trimEndFrame) + trimEndFraction) / Double(fps) }

    // MARK: - Mutations

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

    // MARK: - Sub-frame mutations (ms-precision mode)

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

    // MARK: - Geometry

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
    /// when the trim window is wider than `warpEngageFarSeconds` — the
    /// common case during coarse editing. Otherwise returns a warp whose
    /// `amount` ramps from 0 to 1 via smoothstep as the window tightens,
    /// centered on the trim region with a small padding.
    ///
    /// Engagement looks only at `|trimEnd − trimStart|`. Two reasons:
    /// 1. The default startup state has the playhead at the trim start,
    ///    so a rule based on "any pair close" fires spuriously before
    ///    the user has done anything.
    /// 2. The fisheye's primary purpose is frame-accurate trim editing.
    ///    A playhead approaching a trim handle for seeking is better
    ///    served by the precision afforded by the already-short trim
    ///    window, not by warping on playhead proximity.
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
            // Smoothstep: 3u² − 2u³ with u = (far − window) / (far − near).
            // u ∈ [0, 1] maps to amount ∈ [0, 1] with zero slope at both ends
            // so engagement and release are visually continuous.
            let u = (far - window) / (far - near)
            amount = u * u * (3 - 2 * u)
        }

        // Focus window = trim window + padding, clamped into [0, T].
        let s = trimStartSecondsPrecise
        let e = trimEndSecondsPrecise
        let pad = Self.warpFocusPadSeconds
        let low = max(0, min(s, e) - pad)
        let high = min(T, max(s, e) + pad)
        guard low < high else { return nil }

        return TimelineGeometry.Warp(focus: low...high, scale: Self.warpScale, amount: amount)
    }

    /// Converts a drag translation (in points) to a signed frame delta.
    /// Rounded to nearest frame. Callers capture an anchor frame on first drag
    /// change, then call `anchor + frameDelta(...)` on each update.
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

    // MARK: - Private

    private func secondFloor(_ frame: Int) -> Int { frame / fps }
}
