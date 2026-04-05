//
//  DecoderTests.swift
//  FastGIFTests
//
//  Comprehensive tests for Decoder and DecoderError.
//

import XCTest
import UIKit
import ImageIO
@testable import FastGIF

final class DecoderTests: XCTestCase {

    /// Creates a valid GIF Data blob by encoding test frames through the Encoder (round-trip).
    private func makeTestGIFData(frameCount: Int = 3, delay: Double = 0.1) throws -> Data {
        let frames = Self.makeTestFrames(count: frameCount, delay: delay)
        return try Encoder.encodeGIF(frames: frames)
    }

    // MARK: - DecoderError Tests

    func testDecoderErrorDescriptions() {
        let errors: [DecoderError] = [
            .invalidData,
            .noFrames,
            .noVideoTrack,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription,
                            "Expected non-nil description for \(error)")
        }
    }

    func testDecoderErrorConformsToError() {
        let error: Error = DecoderError.invalidData
        XCTAssertNotNil(error as? DecoderError)
    }

    // MARK: - Decoder GIF Tests

    func testDecodeGIFData() throws {
        let frameCount = 3
        let gifData = try makeTestGIFData(frameCount: frameCount)

        let decodedFrames = try Decoder.decodeImageSource(from: gifData)

        XCTAssertEqual(decodedFrames.count, frameCount,
                       "Decoded frame count should match the encoded frame count")

        for frame in decodedFrames {
            XCTAssertEqual(frame.width, 10)
            XCTAssertEqual(frame.height, 10)
            XCTAssertGreaterThan(frame.delay, 0)
        }
    }

    func testDecodeInvalidData() {
        let garbage = Data([0xFF, 0xD8, 0x00, 0x01, 0x02, 0x03])

        XCTAssertThrowsError(try Decoder.decodeImageSource(from: garbage)) { error in
            // CGImageSource may succeed with garbage data but report 0 frames,
            // resulting in .noFrames rather than .invalidData.
            let decoderError = error as? DecoderError
            XCTAssertTrue(decoderError == .invalidData || decoderError == .noFrames,
                          "Expected .invalidData or .noFrames, got \(String(describing: decoderError))")
        }
    }

    func testDecodeEmptyData() {
        let emptyData = Data()

        XCTAssertThrowsError(try Decoder.decodeImageSource(from: emptyData)) { error in
            // CGImageSource may succeed with empty data but report 0 frames,
            // resulting in .noFrames rather than .invalidData.
            let decoderError = error as? DecoderError
            XCTAssertTrue(decoderError == .invalidData || decoderError == .noFrames,
                          "Expected .invalidData or .noFrames, got \(String(describing: decoderError))")
        }
    }

    func testDecodeSingleImage() throws {
        // Create a single PNG image via UIKit
        let cgImage = Self.makeTestCGImage(width: 20, height: 20)
        let uiImage = UIImage(cgImage: cgImage)
        guard let pngData = uiImage.pngData() else {
            XCTFail("Failed to create PNG data from test image")
            return
        }

        let frame = try Decoder.decodeImage(data: pngData)

        XCTAssertEqual(frame.width, 20)
        XCTAssertEqual(frame.height, 20)
        // Default delay when no animation info is present is 0.1
        XCTAssertEqual(frame.delay, 0.1)
    }

    func testDecodeImageSourceFromGIFRoundTrip() throws {
        let originalFrames = Self.makeTestFrames(count: 3, delay: 0.15)
        let gifData = try Encoder.encodeGIF(frames: originalFrames)

        let decodedFrames = try Decoder.decodeImageSource(from: gifData)

        XCTAssertEqual(decodedFrames.count, originalFrames.count,
                       "Round-trip: decoded frame count should match original")

        // Verify dimensions are preserved
        for (decoded, original) in zip(decodedFrames, originalFrames) {
            XCTAssertEqual(decoded.width, original.width)
            XCTAssertEqual(decoded.height, original.height)
        }
    }

    func testDecodePreservesMinimumDelay() throws {
        // Encode frames with a very small delay (below the 0.02 minimum)
        let frames = Self.makeTestFrames(count: 3, delay: 0.001)
        let gifData = try Encoder.encodeGIF(frames: frames)

        let decodedFrames = try Decoder.decodeImageSource(from: gifData)

        XCTAssertFalse(decodedFrames.isEmpty, "Should decode at least one frame")

        for frame in decodedFrames {
            XCTAssertGreaterThanOrEqual(frame.delay, 0.02,
                                         "Decoded frame delay should be at least 0.02 seconds (minimum enforced by decoder)")
        }
    }
}
