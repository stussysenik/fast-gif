//
//  ProcessingTests.swift
//  FastGIFTests
//
//  Comprehensive XCTest suite for image processing stages.
//

import XCTest
import UIKit
import CoreGraphics
import CoreImage
@testable import FastGIF

final class ProcessingTests: XCTestCase {

    // MARK: - Resize Tests

    func testResizeChangesDimensions() async throws {
        let targetSize = CGSize(width: 20, height: 20)
        let stage = Resize(targetSize: targetSize)
        let frames = [Self.makeTestFrame(width: 10, height: 10)]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].width, 20)
        XCTAssertEqual(output[0].height, 20)
    }

    func testResizePreservesDelay() async throws {
        let targetSize = CGSize(width: 5, height: 5)
        let stage = Resize(targetSize: targetSize)
        let frames = [
            Self.makeTestFrame(delay: 0.1),
            Self.makeTestFrame(delay: 0.25)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output[0].delay, 0.1)
        XCTAssertEqual(output[1].delay, 0.25)
    }

    func testResizeMultipleFrames() async throws {
        let targetSize = CGSize(width: 8, height: 8)
        let stage = Resize(targetSize: targetSize)
        let frames = [
            Self.makeTestFrame(width: 10, height: 10),
            Self.makeTestFrame(width: 20, height: 20),
            Self.makeTestFrame(width: 30, height: 30)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 3)
        for frame in output {
            XCTAssertEqual(frame.width, 8)
            XCTAssertEqual(frame.height, 8)
        }
    }

    func testResizeEmptyInput() async throws {
        let stage = Resize(targetSize: CGSize(width: 5, height: 5))
        let output = try await stage.process([])
        XCTAssertTrue(output.isEmpty)
    }

    func testResizeNonUniformDimensions() async throws {
        let targetSize = CGSize(width: 16, height: 16)
        let stage = Resize(targetSize: targetSize)
        let frames = [
            Self.makeTestFrame(width: 10, height: 20),
            Self.makeTestFrame(width: 50, height: 30),
            Self.makeTestFrame(width: 100, height: 5)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 3)
        for frame in output {
            XCTAssertEqual(frame.width, 16)
            XCTAssertEqual(frame.height, 16)
        }
    }

    // MARK: - Quantize Tests

    func testQuantizeClampsColorsMin() async throws {
        let stage = Quantize(colors: -5)
        // Clamped to 2 internally; verify it processes without error
        let frames = [Self.makeTestFrame()]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 1)
    }

    func testQuantizeClampsColorsMax() async throws {
        let stage = Quantize(colors: 500)
        // Clamped to 256 internally; verify it processes without error
        let frames = [Self.makeTestFrame()]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 1)
    }

    func testQuantizePreservesFrameCount() async throws {
        let stage = Quantize(colors: 64)
        let frames = Array(repeating: Self.makeTestFrame(), count: 5)
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 5)
    }

    func testQuantizePreservesDelay() async throws {
        let stage = Quantize(colors: 16)
        let frames = [
            Self.makeTestFrame(delay: 0.05),
            Self.makeTestFrame(delay: 0.2)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output[0].delay, 0.05)
        XCTAssertEqual(output[1].delay, 0.2)
    }

    func testQuantizeEmptyInput() async throws {
        let stage = Quantize(colors: 256)
        let output = try await stage.process([])
        XCTAssertTrue(output.isEmpty)
    }

    // MARK: - Dither Tests

    func testDitherNoneIsPassthrough() async throws {
        let stage = Dither(.none)
        let frames = [
            Self.makeTestFrame(delay: 0.1),
            Self.makeTestFrame(delay: 0.2)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, frames.count)
        // When algorithm is .none, the original array is returned directly
        // so CGImage references should be identical
        for i in 0..<output.count {
            XCTAssertTrue(output[i].image === frames[i].image,
                          "Frame \(i) image reference should be identical for .none dither")
            XCTAssertEqual(output[i].delay, frames[i].delay)
        }
    }

    func testDitherPreservesFrameCount() async throws {
        let stage = Dither(.floydSteinberg)
        let frames = Array(repeating: Self.makeTestFrame(), count: 4)
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 4)
    }

    func testDitherPreservesDelay() async throws {
        let stage = Dither(.floydSteinberg)
        let frames = [
            Self.makeTestFrame(delay: 0.05),
            Self.makeTestFrame(delay: 0.15)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output[0].delay, 0.05)
        XCTAssertEqual(output[1].delay, 0.15)
    }

    func testDitherAllCases() async throws {
        for algorithm in DitherAlgorithm.allCases {
            let stage = Dither(algorithm)
            let frames = [Self.makeTestFrame()]
            let output = try await stage.process(frames)
            XCTAssertEqual(output.count, 1, "Failed for algorithm: \(algorithm.rawValue)")
        }
    }

    func testDitherAlgorithmCaseCount() {
        XCTAssertEqual(DitherAlgorithm.allCases.count, 4)
    }

    func testDitherAlgorithmIdentifiable() {
        for algorithm in DitherAlgorithm.allCases {
            XCTAssertEqual(algorithm.id, algorithm.rawValue)
        }
    }

    // MARK: - Speed Tests

    func testSpeedHalvesDelay() async throws {
        let stage = Speed(multiplier: 2.0)
        let frames = [Self.makeTestFrame(delay: 0.2)]
        let output = try await stage.process(frames)
        XCTAssertEqual(output[0].delay, 0.1, accuracy: 1e-9)
    }

    func testSpeedDoublesDelay() async throws {
        let stage = Speed(multiplier: 0.5)
        let frames = [Self.makeTestFrame(delay: 0.1)]
        let output = try await stage.process(frames)
        XCTAssertEqual(output[0].delay, 0.2, accuracy: 1e-9)
    }

    func testSpeedPreservesImage() async throws {
        let stage = Speed(multiplier: 2.0)
        let frames = [Self.makeTestFrame()]
        let output = try await stage.process(frames)
        XCTAssertTrue(output[0].image === frames[0].image,
                      "Speed should preserve CGImage references")
    }

    func testSpeedPreservesFrameCount() async throws {
        let stage = Speed(multiplier: 3.0)
        let frames = Array(repeating: Self.makeTestFrame(), count: 6)
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 6)
    }

    // MARK: - Reverse Tests

    func testReverseFlipsOrder() async throws {
        let stage = Reverse()
        let img0 = Self.makeTestCGImage(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let img1 = Self.makeTestCGImage(color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        let img2 = Self.makeTestCGImage(color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        let frames = [
            Frame(image: img0, delay: 0.1),
            Frame(image: img1, delay: 0.2),
            Frame(image: img2, delay: 0.3)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 3)
        XCTAssertTrue(output[0].image === img2)
        XCTAssertEqual(output[0].delay, 0.3)
        XCTAssertTrue(output[1].image === img1)
        XCTAssertEqual(output[1].delay, 0.2)
        XCTAssertTrue(output[2].image === img0)
        XCTAssertEqual(output[2].delay, 0.1)
    }

    func testReverseEmptyInput() async throws {
        let stage = Reverse()
        let output = try await stage.process([])
        XCTAssertTrue(output.isEmpty)
    }

    func testReverseSingleFrame() async throws {
        let stage = Reverse()
        let frame = Self.makeTestFrame(delay: 0.1)
        let output = try await stage.process([frame])
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].delay, 0.1)
    }

    // MARK: - Crop Tests

    func testCropReducesDimensions() async throws {
        let cropRect = CGRect(x: 2, y: 2, width: 5, height: 5)
        let stage = Crop(rect: cropRect)
        let frames = [Self.makeTestFrame(width: 20, height: 20)]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].width, 5)
        XCTAssertEqual(output[0].height, 5)
    }

    func testCropPreservesDelay() async throws {
        let cropRect = CGRect(x: 0, y: 0, width: 5, height: 5)
        let stage = Crop(rect: cropRect)
        let frames = [
            Self.makeTestFrame(width: 10, height: 10, delay: 0.07),
            Self.makeTestFrame(width: 10, height: 10, delay: 0.15)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].delay, 0.07)
        XCTAssertEqual(output[1].delay, 0.15)
    }

    func testCropOutOfboundsReturnsFewer() async throws {
        // Rect extends well beyond the image bounds (image is 10x10)
        let cropRect = CGRect(x: 5, y: 5, width: 100, height: 100)
        let stage = Crop(rect: cropRect)
        let frames = [Self.makeTestFrame(width: 10, height: 10)]
        let output = try await stage.process(frames)
        // CGImage.cropping(to:) returns nil when rect is fully out of bounds,
        // or returns the clipped region. For partial overlap it typically succeeds.
        // At minimum, we verify the stage doesn't crash and returns ≤ input count.
        XCTAssertLessThanOrEqual(output.count, frames.count)
        if let first = output.first {
            // Cropping from (5,5) on a 10x10 image should yield a smaller or equal image
            XCTAssertLessThanOrEqual(first.width, 10)
            XCTAssertLessThanOrEqual(first.height, 10)
        }
    }

    // MARK: - FilterPreset Tests

    func testFilterPresetCaseCount() {
        XCTAssertEqual(FilterPreset.allCases.count, 11)
    }

    func testFilterPresetNoneReturnsNilStage() {
        XCTAssertNil(FilterPreset.none.toStage())
    }

    func testFilterPresetChromeReturnsStage() {
        let stage = FilterPreset.chrome.toStage()
        XCTAssertNotNil(stage)
    }

    func testFilterPresetAllCasesReturnFilterName() {
        for preset in FilterPreset.allCases {
            if preset == .none {
                XCTAssertNil(preset.ciFilterName,
                             "Expected nil ciFilterName for .none")
            } else {
                XCTAssertNotNil(preset.ciFilterName,
                                "Expected non-nil ciFilterName for \(preset.rawValue)")
            }
        }
    }

    func testFilterPresetDisplayName() {
        for preset in FilterPreset.allCases {
            XCTAssertEqual(preset.displayName, preset.rawValue,
                           "displayName should match rawValue for \(preset.rawValue)")
        }
    }

    // MARK: - FilterStage Tests

    func testFilterStageAppliesFilter() async throws {
        let stage = FilterStage(filters: [
            (name: "CIPhotoEffectMono", params: [:])
        ])
        let frames = [Self.makeTestFrame()]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 1)
        // Mono filter should change pixel data — dimensions should remain the same
        XCTAssertEqual(output[0].width, frames[0].width)
        XCTAssertEqual(output[0].height, frames[0].height)
    }

    func testFilterStagePreservesDelay() async throws {
        let stage = FilterStage(filters: [
            (name: "CIPhotoEffectMono", params: [:])
        ])
        let frames = [
            Self.makeTestFrame(delay: 0.05),
            Self.makeTestFrame(delay: 0.3)
        ]
        let output = try await stage.process(frames)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(output[0].delay, 0.05)
        XCTAssertEqual(output[1].delay, 0.3)
    }

    func testFilterStageEmptyInput() async throws {
        let stage = FilterStage(filters: [
            (name: "CIPhotoEffectMono", params: [:])
        ])
        let output = try await stage.process([])
        XCTAssertTrue(output.isEmpty)
    }

    // MARK: - ProcessingError Tests

    func testProcessingErrorDescription() {
        let error = ProcessingError.resizeFailed
        XCTAssertEqual(error.errorDescription, "Resize failed")
    }
}
