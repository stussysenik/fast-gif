//
//  PreviewParityTests.swift
//  FastGIFTests
//
//  Witness for proposition P3 (quality-verification capability):
//
//      preview_color_set(frame) ≡ export_color_set(frame, .draft)
//
//  The preview still-frame path (`Encoder.previewFrame`) and the GIF export path
//  (`Encoder.encodeGIF`) share the same Rust NeuQuant quantizer. Given matching
//  `colors` and `quality`, the set of colors a frame resolves to must be
//  identical regardless of which path produced it. If they ever diverge, the
//  preview is lying about what the export will ship.
//

import XCTest
import CoreGraphics
@testable import FastGIF

final class PreviewParityTests: XCTestCase {

    /// P3: preview palette equals draft-export palette, color-for-color.
    func testPreviewColorSetMatchesDraftExport() throws {
        let frame = Self.makeGradientFrame(width: 48, height: 48)
        let colors = 16
        let factor = Quality.draft.sampleFactor

        // Preview path: single-frame quantize via the Rust preview FFI.
        let preview = Encoder.previewFrame(frame, colors: colors, quality: factor)
        let previewSet = Self.colorSet(of: preview.image)

        // Export path: encode a one-frame GIF at the same colors/quality, decode it back.
        let gifData = try Encoder.encodeGIF(frames: [frame], colors: colors, quality: factor)
        let decoded = try Decoder.decodeImageSource(from: gifData)
        XCTAssertEqual(decoded.count, 1)
        let exportSet = Self.colorSet(of: decoded[0].image)

        XCTAssertFalse(previewSet.isEmpty, "preview produced no colors")
        XCTAssertLessThanOrEqual(previewSet.count, colors, "preview exceeded color budget")
        XCTAssertEqual(previewSet, exportSet,
                       "preview palette diverged from draft export — preview is not WYSIWYG")
    }

    /// The parity must hold across palette sizes, not just one.
    func testPreviewParityAcrossColorBudgets() throws {
        let frame = Self.makeGradientFrame(width: 40, height: 40)
        let factor = Quality.draft.sampleFactor

        for colors in [8, 32, 64] {
            let preview = Encoder.previewFrame(frame, colors: colors, quality: factor)
            let previewSet = Self.colorSet(of: preview.image)

            let gifData = try Encoder.encodeGIF(frames: [frame], colors: colors, quality: factor)
            let decoded = try Decoder.decodeImageSource(from: gifData)
            let exportSet = Self.colorSet(of: decoded[0].image)

            XCTAssertEqual(previewSet, exportSet,
                           "preview/export palette diverged at \(colors) colors")
        }
    }

    // MARK: - Helpers

    /// A deterministic RGB gradient frame (no RNG) so quantization is exercised
    /// with many distinct colors and the result is reproducible.
    static func makeGradientFrame(width: Int, height: Int) -> Frame {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                bytes[o]     = UInt8(255 * x / max(width - 1, 1))
                bytes[o + 1] = UInt8(255 * y / max(height - 1, 1))
                bytes[o + 2] = UInt8(255 * (x + y) / max(width + height - 2, 1))
                bytes[o + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return Frame(image: cg, delay: 0.1)
    }

    /// Distinct RGB colors in an image, sampled by rendering into a known
    /// deviceRGB buffer so both paths are compared on identical footing.
    static func colorSet(of image: CGImage) -> Set<UInt32> {
        let w = image.width
        let h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var set = Set<UInt32>()
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let packed = UInt32(buf[i]) << 16 | UInt32(buf[i + 1]) << 8 | UInt32(buf[i + 2])
            set.insert(packed)
        }
        return set
    }
}
