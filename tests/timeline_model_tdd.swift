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

    // MARK: Mutations

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

    // MARK: Geometry

    /// Converts a drag translation (in points) to a signed frame delta.
    /// Rounded to nearest frame. Callers capture an anchor frame on first
    /// drag change, then call `anchor + frameDelta(...)` on each update.
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

exit(Int32(t.report()))
