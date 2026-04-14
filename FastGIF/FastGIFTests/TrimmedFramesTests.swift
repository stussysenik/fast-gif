//
//  TrimmedFramesTests.swift
//  FastGIFTests
//
//  Covers the in-memory trim window — `GIFProject.trimmedFrames` slices
//  `document.frames` by `trimStart`/`trimEnd` so retrim never re-decodes.
//  These tests pin the boundary semantics so they don't drift.
//

import XCTest
@testable import FastGIF

@MainActor
final class TrimmedFramesTests: XCTestCase {

    /// Helper — fresh project pre-loaded with `count` frames at 0.1s each.
    private func makeProject(frameCount: Int) -> GIFProject {
        let project = GIFProject()
        let frames = Self.makeTestFrames(count: frameCount, delay: 0.1)
        project.document = GIFDocument(frames: frames, loopCount: 0)
        project.videoDuration = Double(frameCount) * 0.1
        return project
    }

    func test_trimmedFrames_returnsAllFrames_whenTrimEndIsNil() {
        let project = makeProject(frameCount: 100)
        XCTAssertEqual(project.trimmedFrames.count, 100)
    }

    func test_trimmedFrames_returnsSubrange_forValidTrimWindow() {
        // 100 frames @ 0.1s each = 10s total.
        // trim 2.5s..5.0s → frames [25, 50) → 25 frames.
        let project = makeProject(frameCount: 100)
        project.trimStart = 2.5
        project.trimEnd = 5.0
        XCTAssertEqual(project.trimmedFrames.count, 25,
                       "expected 25 frames in [2.5s, 5.0s)")
    }

    func test_trimmedFrames_clampsTrimEndToDocumentLength() {
        let project = makeProject(frameCount: 50)
        project.trimStart = 0
        project.trimEnd = 999  // way past document
        XCTAssertEqual(project.trimmedFrames.count, 50)
    }

    func test_trimmedFrames_clampsNegativeStart() {
        let project = makeProject(frameCount: 50)
        project.trimStart = -10
        project.trimEnd = nil
        XCTAssertEqual(project.trimmedFrames.count, 50)
    }

    func test_trimmedFrames_returnsEmpty_whenStartExceedsEnd() {
        let project = makeProject(frameCount: 50)
        project.trimStart = 4.0
        project.trimEnd = 1.0  // inverted
        XCTAssertEqual(project.trimmedFrames.count, 0)
    }

    func test_importVideo_resetsTrim_so_retrimNeverRefersToStaleSourceCoords() async {
        // The bug being pinned: after importVideo runs, trim must be reset
        // to (0, document-length) so subsequent timeline math is consistent.
        // We can't actually call importVideo without a video file, so we
        // just exercise the explicit reset hook.
        let project = makeProject(frameCount: 30)
        project.trimStart = 1.0
        project.trimEnd = 2.0

        // Simulate a fresh import — replace frames + reset trim.
        let frames = Self.makeTestFrames(count: 60, delay: 0.1)
        project.document = GIFDocument(frames: frames, loopCount: 0)
        project.resetTrimToDocumentBounds()

        XCTAssertEqual(project.trimStart, 0.0, accuracy: 1e-9)
        XCTAssertNil(project.trimEnd)
        XCTAssertEqual(project.videoDuration, 6.0, accuracy: 1e-9,
                       "videoDuration must match the new document, not the prior source")
    }
}
