//
//  KernelTests.swift
//  FastGIFTests
//
//  Tests for Kernel types: Frame, GIFDocument, Pipeline, Stage
//

import XCTest
import CoreGraphics
import UIKit
@testable import FastGIF

// MARK: - Mock Stages

/// A stage that records how many times it was called and optionally transforms frames.
/// Reference-type counter so struct Stage implementations can mutate it
/// without needing a `mutating` method (Stage.process is non-mutating).
final class CallCounter {
    var value = 0
}

struct MockStage: Stage {
    let name: String
    let callCounter = CallCounter()
    var callCount: Int { callCounter.value }
    let transform: ([Frame]) -> [Frame]

    init(name: String = "MockStage", transform: @escaping ([Frame]) -> [Frame] = { $0 }) {
        self.name = name
        self.transform = transform
    }

    func process(_ frames: [Frame]) async throws -> [Frame] {
        callCounter.value += 1
        return transform(frames)
    }
}

/// A stage that waits for a given duration, then throws if cancelled.
struct DelayedStage: Stage {
    let delay: TimeInterval

    init(delay: TimeInterval = 2.0) {
        self.delay = delay
    }

    func process(_ frames: [Frame]) async throws -> [Frame] {
        try await Task.sleep(for: .seconds(delay))
        return frames
    }
}

// MARK: - Frame Tests

final class FrameTests: XCTestCase {

    func testFrameDefaultDelay() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frame = Frame(image: cgImage)
        XCTAssertEqual(frame.delay, 0.1, "Default delay should be 0.1 seconds")
    }

    func testFrameCustomDelay() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frame = Frame(image: cgImage, delay: 0.5)
        XCTAssertEqual(frame.delay, 0.5, "Custom delay should be preserved")
    }

    func testFrameUniqueIDs() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frame1 = Frame(image: cgImage)
        let frame2 = Frame(image: cgImage)
        XCTAssertNotEqual(frame1.id, frame2.id, "Two frames should have different IDs")
    }

    func testFrameComputedDimensions() {
        let width = 20
        let height = 30
        let cgImage = XCTestCase.makeTestCGImage(width: width, height: height)
        let frame = Frame(image: cgImage)

        XCTAssertEqual(frame.width, width, "Frame width should match CGImage width")
        XCTAssertEqual(frame.height, height, "Frame height should match CGImage height")
        XCTAssertEqual(frame.size, CGSize(width: width, height: height), "Frame size should match CGImage dimensions")
    }

    func testFrameIdentifiable() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frame = Frame(image: cgImage)
        // Frame conforms to Identifiable — id is accessible and stable
        let _: UUID = frame.id
        // Also verify it works in a collection that requires Identifiable
        let frames: [any Identifiable] = [frame]
        XCTAssertEqual(frames.count, 1)
    }
}

// MARK: - GIFDocument Tests

final class GIFDocumentTests: XCTestCase {

    func testDocumentDefaultInit() {
        let doc = GIFDocument()
        XCTAssertTrue(doc.frames.isEmpty, "Default document should have empty frames")
        XCTAssertEqual(doc.loopCount, 0, "Default loopCount should be 0")
    }

    func testDocumentCustomInit() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frames = [
            Frame(image: cgImage, delay: 0.1),
            Frame(image: cgImage, delay: 0.2),
            Frame(image: cgImage, delay: 0.3)
        ]
        let doc = GIFDocument(frames: frames, loopCount: 3)
        XCTAssertEqual(doc.frameCount, 3, "Frame count should be 3")
        XCTAssertEqual(doc.loopCount, 3, "Loop count should be 3")
        XCTAssertEqual(doc.frames.count, 3, "Frames array count should be 3")
    }

    func testDocumentDuration() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frames = [
            Frame(image: cgImage, delay: 0.1),
            Frame(image: cgImage, delay: 0.2),
            Frame(image: cgImage, delay: 0.3)
        ]
        let doc = GIFDocument(frames: frames)
        XCTAssertEqual(doc.duration, 0.6, accuracy: 0.001, "Duration should be the sum of frame delays")
    }

    func testDocumentDurationEmpty() {
        let doc = GIFDocument()
        XCTAssertEqual(doc.duration, 0.0, "Duration of empty document should be 0.0")
    }

    func testDocumentFrameCount() {
        let cgImage = XCTestCase.makeTestCGImage()
        let frames = [
            Frame(image: cgImage),
            Frame(image: cgImage),
            Frame(image: cgImage),
            Frame(image: cgImage),
            Frame(image: cgImage)
        ]
        let doc = GIFDocument(frames: frames)
        XCTAssertEqual(doc.frameCount, 5, "Frame count should be 5")
    }

    func testDocumentFrameCountEmpty() {
        let doc = GIFDocument()
        XCTAssertEqual(doc.frameCount, 0, "Frame count of empty document should be 0")
    }
}

// MARK: - Stage Protocol Tests

final class StageTests: XCTestCase {

    func testPassthroughPreservesFrames() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let frames = [
            Frame(image: cgImage, delay: 0.1),
            Frame(image: cgImage, delay: 0.2),
            Frame(image: cgImage, delay: 0.3)
        ]
        let passthrough = Passthrough()
        let output = try await passthrough.process(frames)
        XCTAssertEqual(output.count, frames.count, "Passthrough should preserve frame count")
        for (outputFrame, originalFrame) in zip(output, frames) {
            XCTAssertEqual(outputFrame.delay, originalFrame.delay, "Passthrough should preserve frame delays")
        }
    }

    func testPassthroughPreservesImageData() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let frame = Frame(image: cgImage, delay: 0.1)
        let passthrough = Passthrough()
        let output = try await passthrough.process([frame])
        XCTAssertEqual(output.count, 1)
        XCTAssertTrue(output[0].image === cgImage, "Passthrough should return the same CGImage reference")
    }

    func testPassthroughEmptyInput() async throws {
        let passthrough = Passthrough()
        let output = try await passthrough.process([])
        XCTAssertTrue(output.isEmpty, "Passthrough should return empty array for empty input")
    }
}

// MARK: - Pipeline Tests

final class PipelineTests: XCTestCase {

    /// A stage that appends a marker frame with a given delay to track execution order.
    struct MarkerStage: Stage {
        let markerDelay: Double
        let callCounter = CallCounter()
        var callCount: Int { callCounter.value }

        func process(_ frames: [Frame]) async throws -> [Frame] {
            callCounter.value += 1
            let markerImage = XCTestCase.makeTestCGImage()
            return frames + [Frame(image: markerImage, delay: markerDelay)]
        }
    }

    func testPipelineSequentialExecution() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage, delay: 0.05)]

        let pipeline = Pipeline(stages: [
            MarkerStage(markerDelay: 1.0),
            MarkerStage(markerDelay: 2.0),
            MarkerStage(markerDelay: 3.0)
        ])

        let output = try await pipeline.run(input)
        // 1 input frame + 3 markers = 4 total
        XCTAssertEqual(output.count, 4, "Pipeline should produce 1 input + 3 marker frames")

        // Verify markers were appended in order
        XCTAssertEqual(output[1].delay, 1.0, "First marker should have delay 1.0")
        XCTAssertEqual(output[2].delay, 2.0, "Second marker should have delay 2.0")
        XCTAssertEqual(output[3].delay, 3.0, "Third marker should have delay 3.0")
    }

    func testPipelineEmptyStages() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [
            Frame(image: cgImage, delay: 0.1),
            Frame(image: cgImage, delay: 0.2)
        ]

        let pipeline = Pipeline(stages: [])
        let output = try await pipeline.run(input)

        XCTAssertEqual(output.count, 2, "Pipeline with no stages should return input unchanged")
        XCTAssertEqual(output[0].delay, 0.1)
        XCTAssertEqual(output[1].delay, 0.2)
    }

    func testPipelineProgressReporting() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage)]

        var progressValues: [Double] = []

        let pipeline = Pipeline(stages: [
            MockStage(name: "A"),
            MockStage(name: "B"),
            MockStage(name: "C")
        ])

        _ = try await pipeline.run(input) { progress in
            progressValues.append(progress)
        }

        // Progress should start at 0/3 = 0.0, then 1/3 ≈ 0.333, then 2/3 ≈ 0.666, and finally 1.0
        XCTAssertTrue(progressValues.count >= 3, "Should receive at least 3 progress updates (one per stage + final)")
        XCTAssertEqual(progressValues.first ?? -1, 0.0, "First progress should be 0.0")

        // Verify monotonically increasing
        for i in 1..<progressValues.count {
            XCTAssertGreaterThan(progressValues[i], progressValues[i - 1],
                                 "Progress values should be monotonically increasing")
        }
    }

    func testPipelineProgressCompletesAt1() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage)]

        var lastProgress: Double = -1

        let pipeline = Pipeline(stages: [
            MockStage(name: "Stage1"),
            MockStage(name: "Stage2")
        ])

        _ = try await pipeline.run(input) { progress in
            lastProgress = progress
        }

        XCTAssertEqual(lastProgress, 1.0, "Final progress value should be 1.0")
    }

    func testPipelinePreservesFrameDelays() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let delays = [0.05, 0.1, 0.2, 0.4]
        let input = delays.map { Frame(image: XCTestCase.makeTestCGImage(), delay: $0) }

        let pipeline = Pipeline(stages: [
            MockStage(name: "PassthroughA"),
            MockStage(name: "PassthroughB")
        ])

        let output = try await pipeline.run(input)
        XCTAssertEqual(output.count, input.count, "Frame count should be preserved")
        for (outputFrame, originalFrame) in zip(output, input) {
            XCTAssertEqual(outputFrame.delay, originalFrame.delay, accuracy: 0.001,
                           "Frame delays should survive the pipeline")
        }
    }

    func testPipelineCancellation() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage)]

        let pipeline = Pipeline(stages: [
            DelayedStage(delay: 10.0)
        ])

        let task = Task {
            try await pipeline.run(input)
        }

        // Give the task a moment to start, then cancel
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError but pipeline completed successfully")
        } catch is CancellationError {
            // Expected
        } catch {
            // Some paths may throw other errors; that's also acceptable for cancellation
            XCTAssertTrue(Task.isCancelled || error is CancellationError,
                           "Expected cancellation-related error, got: \(error)")
        }
    }

    func testPipelineResultBuilderSingle() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage, delay: 0.1)]

        let pipeline = Pipeline {
            Passthrough()
        }

        let output = try await pipeline.run(input)
        XCTAssertEqual(output.count, 1, "Single-stage pipeline should produce correct output")
        XCTAssertEqual(output[0].delay, 0.1)
        XCTAssertEqual(pipeline.stages.count, 1, "Pipeline should have exactly 1 stage")
    }

    func testPipelineResultBuilderMultiple() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage, delay: 0.05)]

        let pipeline = Pipeline {
            MockStage(name: "First")
            MockStage(name: "Second")
            MockStage(name: "Third")
        }

        XCTAssertEqual(pipeline.stages.count, 3, "Pipeline should have 3 stages")

        let output = try await pipeline.run(input)
        XCTAssertEqual(output.count, 1, "All stages are passthrough, so output count matches input")
        XCTAssertEqual(output[0].delay, 0.05, "Frame delay should be preserved through all stages")
    }

    func testPipelineWithConditionalStages() async throws {
        let cgImage = XCTestCase.makeTestCGImage()
        let input = [Frame(image: cgImage)]

        let includeResize = true
        let includeDither = false

        let pipeline = Pipeline {
            Passthrough()
            if includeResize {
                MockStage(name: "Resize")
            }
            if includeDither {
                MockStage(name: "Dither")
            } else {
                MockStage(name: "NoDither")
            }
        }

        // Expected: Passthrough + Resize + NoDither = 3 stages
        XCTAssertEqual(pipeline.stages.count, 3,
                       "Conditional builder should produce 3 stages (Passthrough + Resize + NoDither)")

        let output = try await pipeline.run(input)
        XCTAssertEqual(output.count, 1, "Output should have 1 frame")
    }
}
