//
//  EncoderTests.swift
//  FastGIFTests
//
//  Comprehensive tests for Encoder, ExportFormat, and EncoderError.
//

import XCTest
import UIKit
import MobileCoreServices
@testable import FastGIF

final class EncoderTests: XCTestCase {

    // MARK: - ExportFormat Tests

    func testExportFormatCaseCount() {
        XCTAssertEqual(ExportFormat.allCases.count, 6)
    }

    func testExportFormatDisplayNames() {
        XCTAssertEqual(ExportFormat.gif.displayName, "GIF")
        XCTAssertEqual(ExportFormat.apng.displayName, "APNG")
        XCTAssertEqual(ExportFormat.webp.displayName, "WebP")
        XCTAssertEqual(ExportFormat.mp4.displayName, "MP4")
        XCTAssertEqual(ExportFormat.mov.displayName, "MOV")
        XCTAssertEqual(ExportFormat.heic.displayName, "HEIC")
    }

    func testExportFormatFileExtensions() {
        XCTAssertEqual(ExportFormat.gif.fileExtension, "gif")
        XCTAssertEqual(ExportFormat.apng.fileExtension, "apng")
        XCTAssertEqual(ExportFormat.webp.fileExtension, "webp")
        XCTAssertEqual(ExportFormat.mp4.fileExtension, "mp4")
        XCTAssertEqual(ExportFormat.mov.fileExtension, "mov")
        XCTAssertEqual(ExportFormat.heic.fileExtension, "heic")
    }

    func testExportFormatTransparency() {
        XCTAssertTrue(ExportFormat.gif.supportsTransparency)
        XCTAssertTrue(ExportFormat.apng.supportsTransparency)
        XCTAssertTrue(ExportFormat.webp.supportsTransparency)
        XCTAssertTrue(ExportFormat.heic.supportsTransparency)
        XCTAssertFalse(ExportFormat.mp4.supportsTransparency)
        XCTAssertFalse(ExportFormat.mov.supportsTransparency)
    }

    func testExportFormatUTIs() {
        XCTAssertEqual(ExportFormat.gif.uti as String, kUTTypeGIF as String)
        XCTAssertEqual(ExportFormat.apng.uti as String, "public.png")
        XCTAssertEqual(ExportFormat.webp.uti as String, "org.webmproject.webp")
        XCTAssertEqual(ExportFormat.mp4.uti as String, kUTTypeMPEG4 as String)
        XCTAssertEqual(ExportFormat.mov.uti as String, kUTTypeQuickTimeMovie as String)
        XCTAssertEqual(ExportFormat.heic.uti as String, "public.heic")
    }

    func testExportFormatIdentifiable() {
        for format in ExportFormat.allCases {
            XCTAssertEqual(format.id, format.rawValue)
        }
    }

    func testExportFormatCaseIterable() {
        let allCases = ExportFormat.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.gif))
        XCTAssertTrue(allCases.contains(.apng))
        XCTAssertTrue(allCases.contains(.webp))
        XCTAssertTrue(allCases.contains(.mp4))
        XCTAssertTrue(allCases.contains(.mov))
        XCTAssertTrue(allCases.contains(.heic))
    }

    // MARK: - EncoderError Tests

    func testEncoderErrorDescriptions() {
        let errors: [EncoderError] = [
            .creationFailed,
            .finalizeFailed,
            .noFrames,
            .bufferPoolFailed,
            .bufferCreationFailed,
            .formatUnsupported,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Expected non-nil description for \(error)")
        }
    }

    func testEncoderErrorConformsToError() {
        let error: Error = EncoderError.noFrames
        XCTAssertNotNil(error as? EncoderError)
    }

    // MARK: - Encoder GIF Tests

    func testEncodeGIFFromFrames() throws {
        let frames = Self.makeTestFrames(count: 3)
        let data = try Encoder.encodeGIF(frames: frames)

        XCTAssertFalse(data.isEmpty, "GIF data should not be empty")

        // Verify GIF header: starts with "GIF" (GIF87a or GIF89a)
        let headerBytes = [UInt8](data.prefix(3))
        let gifSignature: [UInt8] = [0x47, 0x49, 0x46] // "GIF"
        XCTAssertEqual(headerBytes, gifSignature,
                       "GIF data should start with 'GIF' header bytes")
    }

    func testEncodeGIFThrowsOnEmpty() {
        XCTAssertThrowsError(try Encoder.encodeGIF(frames: [])) { error in
            XCTAssertNotNil(error as? EncoderError)
            XCTAssertEqual(error as? EncoderError, .noFrames)
        }
    }

    func testEncodeGIFWithCustomColors() throws {
        let frames = Self.makeTestFrames(count: 3)

        // Encode with low color count
        let dataLowColors = try Encoder.encodeGIF(frames: frames, colors: 8)
        XCTAssertFalse(dataLowColors.isEmpty)

        // Encode with high color count
        let dataHighColors = try Encoder.encodeGIF(frames: frames, colors: 256)
        XCTAssertFalse(dataHighColors.isEmpty)

        // Both should be valid GIFs
        for data in [dataLowColors, dataHighColors] {
            let headerBytes = [UInt8](data.prefix(3))
            let gifSignature: [UInt8] = [0x47, 0x49, 0x46] // "GIF"
            XCTAssertEqual(headerBytes, gifSignature)
        }
    }

    func testEncodeGIFSingleFrame() throws {
        let frames = Self.makeTestFrames(count: 1)
        let data = try Encoder.encodeGIF(frames: frames)

        XCTAssertFalse(data.isEmpty)

        // Verify it's a valid GIF
        let headerBytes = [UInt8](data.prefix(3))
        let gifSignature: [UInt8] = [0x47, 0x49, 0x46] // "GIF"
        XCTAssertEqual(headerBytes, gifSignature)

        // Should be decodable back to 1 frame
        let decoded = try Decoder.decodeImageSource(from: data)
        XCTAssertEqual(decoded.count, 1)
    }

    // MARK: - Encoder APNG Tests

    func testEncodeAPNGFromFrames() throws {
        let frames = Self.makeTestFrames(count: 3)
        let data = try Encoder.encodeAPNG(frames: frames)

        XCTAssertFalse(data.isEmpty, "APNG data should not be empty")

        // Verify PNG signature: 137, 80, 78, 71, 13, 10, 26, 10
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        let headerBytes = [UInt8](data.prefix(8))
        XCTAssertEqual(headerBytes, pngSignature,
                       "APNG data should start with PNG signature bytes")
    }

    func testEncodeAPNGThrowsOnEmpty() {
        XCTAssertThrowsError(try Encoder.encodeAPNG(frames: [])) { error in
            // CGImageDestinationCreateWithData with 0 frames still succeeds,
            // but CGImageDestinationFinalize with no added frames fails.
            XCTAssertNotNil(error as? EncoderError)
        }
    }

    // MARK: - Encoder WebP / HEIC Tests

    func testEncodeWebPIsStatic() async throws {
        let frames = Self.makeTestFrames(count: 3)

        // WebP CGImageDestination may not be available on all simulator runtimes.
        // If unsupported, the encoder throws .formatUnsupported — accept that as a pass.
        let data: Data
        do {
            data = try await Encoder.encode(frames: frames, format: .webp)
        } catch let error as EncoderError where error == .formatUnsupported {
            // WebP not supported on this runtime — nothing to assert, test passes
            return
        }

        XCTAssertFalse(data.isEmpty, "WebP data should not be empty")

        // WebP should only contain 1 frame (static image, known limitation)
        // Verify by decoding — CGImageSource for WebP typically reports 1 frame
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let count = CGImageSourceGetCount(source)
            XCTAssertEqual(count, 1, "WebP should encode only the first frame (known limitation)")
        }
    }

    func testEncodeHEICIsStatic() async throws {
        let frames = Self.makeTestFrames(count: 3)

        // HEIC CGImageDestination may not be available on all simulator runtimes.
        // If unsupported, the encoder throws .formatUnsupported — accept that as a pass.
        let data: Data
        do {
            data = try await Encoder.encode(frames: frames, format: .heic)
        } catch let error as EncoderError where error == .formatUnsupported {
            // HEIC not supported on this runtime — nothing to assert, test passes
            return
        }

        XCTAssertFalse(data.isEmpty, "HEIC data should not be empty")

        // HEIC should only contain 1 frame (static image, known limitation)
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let count = CGImageSourceGetCount(source)
            XCTAssertEqual(count, 1, "HEIC should encode only the first frame (known limitation)")
        }
    }

    // MARK: - Encoder Dispatch Tests

    func testEncodeDispatchesCorrectly() async throws {
        let frames = Self.makeTestFrames(count: 3)
        let data = try await Encoder.encode(frames: frames, format: .gif)

        XCTAssertFalse(data.isEmpty, "encode() for .gif should return non-empty data")

        // Verify it's a GIF by checking header
        let headerBytes = [UInt8](data.prefix(3))
        let gifSignature: [UInt8] = [0x47, 0x49, 0x46] // "GIF"
        XCTAssertEqual(headerBytes, gifSignature,
                       "encode(.gif) should dispatch to encodeGIF and return GIF data")
    }
}
