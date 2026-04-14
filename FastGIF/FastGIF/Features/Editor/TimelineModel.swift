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

    // MARK: - Mutations

    mutating func moveTrimStart(to target: Int) {
        let clamped = max(0, min(target, trimEndFrame - 1))
        guard clamped != trimStartFrame else { return }
        let oldSecond = secondFloor(trimStartFrame)
        trimStartFrame = clamped
        frameStepToken &+= 1
        if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
        if clamped == 0 { endpointDetentToken &+= 1 }
    }

    mutating func moveTrimEnd(to target: Int) {
        let clamped = max(trimStartFrame + 1, min(target, lastFrame))
        guard clamped != trimEndFrame else { return }
        let oldSecond = secondFloor(trimEndFrame)
        trimEndFrame = clamped
        frameStepToken &+= 1
        if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
        if clamped == lastFrame { endpointDetentToken &+= 1 }
    }

    mutating func movePlayhead(to target: Int) {
        let clamped = max(0, min(target, lastFrame))
        guard clamped != playheadFrame else { return }
        let oldSecond = secondFloor(playheadFrame)
        let wasInTrim = playheadIsInTrim
        playheadFrame = clamped
        frameStepToken &+= 1
        if oldSecond != secondFloor(clamped) { secondDetentToken &+= 1 }
        if clamped == 0 || clamped == lastFrame { endpointDetentToken &+= 1 }
        if wasInTrim != playheadIsInTrim { trimCrossingToken &+= 1 }
    }

    // MARK: - Geometry

    /// Converts a drag translation (in points) to a signed frame delta.
    /// Rounded to nearest frame. Callers capture an anchor frame on first drag
    /// change, then call `anchor + frameDelta(...)` on each update.
    func frameDelta(forPixelDelta dx: CGFloat, railWidth: CGFloat) -> Int {
        guard railWidth > 0, lastFrame > 0 else { return 0 }
        let pixelsPerFrame = railWidth / CGFloat(lastFrame)
        return Int((dx / pixelsPerFrame).rounded())
    }

    /// x-coordinate (points) for a given frame on a rail of given width.
    func xPosition(for frame: Int, railWidth: CGFloat) -> CGFloat {
        guard lastFrame > 0 else { return 0 }
        let clamped = max(0, min(frame, lastFrame))
        return CGFloat(clamped) * railWidth / CGFloat(lastFrame)
    }

    // MARK: - Private

    private func secondFloor(_ frame: Int) -> Int { frame / fps }
}
