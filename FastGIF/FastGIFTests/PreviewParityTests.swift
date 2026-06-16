//
//  PreviewParityTests.swift
//  FastGIFTests
//
//  Witness for proposition P3 (quality-verification capability):
//
//      preview_color_set(frame) ≡ export_color_set(frame, .draft)
//
//  The preview still-frame path (`Encoder.previewFrameGlobal`) and the GIF export
//  path (`Encoder.encodeGIFGlobal`, draft/nearest) share the same global palette
//  and the same deterministic `nearest_index` lookup. Given matching `colors` and
//  `quality`, the set of colors a frame resolves to must be identical regardless
//  of which path produced it. If they ever diverge, the preview is lying about
//  what the export will ship.
//

import XCTest
import CoreGraphics
@testable import FastGIF

final class PreviewParityTests: XCTestCase {

    /// P3: global-preview palette equals draft (nearest) global-export palette,
    /// color-for-color, for a frame inside a clip.
    func testPreviewColorSetMatchesDraftExport() throws {
        let clip = Self.makeClip(count: 6, width: 48, height: 48)
        let target = 2
        let colors = 16
        let factor = Quality.draft.sampleFactor

        // Preview path: quantize the target frame against the global palette.
        let preview = Encoder.previewFrameGlobal(frames: clip, target: target, colors: colors, quality: factor)
        let previewSet = Self.colorSet(of: preview.image)

        // Export path: global GIF, nearest (draft, no diffusion). Decode, sample target.
        let gifData = try Encoder.encodeGIFGlobal(frames: clip, colors: colors, quality: factor, dither: false)
        let decoded = try Decoder.decodeImageSource(from: gifData)
        XCTAssertEqual(decoded.count, clip.count)
        let exportSet = Self.colorSet(of: decoded[target].image)

        XCTAssertFalse(previewSet.isEmpty, "preview produced no colors")
        XCTAssertLessThanOrEqual(previewSet.count, colors, "preview exceeded color budget")
        XCTAssertEqual(previewSet, exportSet,
                       "preview palette diverged from draft export — preview is not WYSIWYG")
    }

    /// The parity must hold across palette sizes, not just one.
    func testPreviewParityAcrossColorBudgets() throws {
        let clip = Self.makeClip(count: 5, width: 40, height: 40)
        let target = 1
        let factor = Quality.draft.sampleFactor

        for colors in [8, 32, 64] {
            let preview = Encoder.previewFrameGlobal(frames: clip, target: target, colors: colors, quality: factor)
            let previewSet = Self.colorSet(of: preview.image)

            let gifData = try Encoder.encodeGIFGlobal(frames: clip, colors: colors, quality: factor, dither: false)
            let decoded = try Decoder.decodeImageSource(from: gifData)
            let exportSet = Self.colorSet(of: decoded[target].image)

            XCTAssertEqual(previewSet, exportSet,
                           "preview/export palette diverged at \(colors) colors")
        }
    }

    // MARK: - Helpers

    /// A short clip of gradient frames that pan diagonally, so the global palette
    /// is trained over genuinely varying content (not N identical frames).
    static func makeClip(count: Int, width: Int, height: Int) -> [Frame] {
        (0..<count).map { n in makeGradientFrame(width: width, height: height, shift: n * 12) }
    }

    /// A deterministic RGB gradient frame (no RNG) so quantization is exercised
    /// with many distinct colors and the result is reproducible.
    static func makeGradientFrame(width: Int, height: Int, shift: Int = 0) -> Frame {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let o = (y * width + x) * 4
                let sx = (x + shift) % width
                bytes[o]     = UInt8(255 * sx / max(width - 1, 1))
                bytes[o + 1] = UInt8(255 * y / max(height - 1, 1))
                bytes[o + 2] = UInt8(255 * (sx + y) / max(width + height - 2, 1))
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
