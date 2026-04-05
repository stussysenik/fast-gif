import Foundation
import CoreGraphics

/// iMessage sticker size tiers per Apple HIG.
enum StickerSize: String, CaseIterable, Identifiable {
    case small = "Small"   // 100x100 pt (300x300 @3x)
    case medium = "Medium" // 136x136 pt (408x408 @3x)
    case large = "Large"   // 206x206 pt (618x618 @3x)

    var id: String { rawValue }

    var pixels: CGSize {
        switch self {
        case .small: CGSize(width: 300, height: 300)
        case .medium: CGSize(width: 408, height: 408)
        case .large: CGSize(width: 618, height: 618)
        }
    }

    /// Apple's hard limit for stickers.
    static let maxFileSize: Int = 500_000 // 500 KB
    static let maxFPS: Double = 15
}

/// Optimizes a GIF project for iMessage sticker export.
/// Automatically reduces quality/size to fit Apple's 500KB constraint.
enum StickerOptimizer {

    struct Result {
        let data: Data
        let format: ExportFormat
        let size: StickerSize
        let fileSize: Int
        let isWithinLimit: Bool
    }

    static func optimize(
        frames: [Frame],
        size: StickerSize,
        loopCount: Int = 0
    ) async throws -> Result {
        // Step 1: Resize to sticker dimensions
        let resized = try await Resize(targetSize: size.pixels).process(frames)

        // Step 2: Cap frame rate at 15 FPS
        let capped = resized.map { frame in
            Frame(image: frame.image, delay: max(frame.delay, 1.0 / StickerSize.maxFPS))
        }

        // Step 3: Try APNG first (best iMessage format)
        var data = try Encoder.encodeAPNG(frames: capped, loopCount: loopCount)

        // Step 4: If over 500KB, progressively reduce quality
        var colors = 256
        while data.count > StickerSize.maxFileSize && colors > 16 {
            colors /= 2
            let quantized = try await Quantize(colors: colors).process(capped)
            data = try Encoder.encodeAPNG(frames: quantized, loopCount: loopCount)
        }

        // Step 5: If still over, reduce frame count
        var optimizedFrames = capped
        while data.count > StickerSize.maxFileSize && optimizedFrames.count > 4 {
            // Remove every other frame, double remaining delays
            optimizedFrames = optimizedFrames.enumerated().compactMap { i, f in
                i.isMultiple(of: 2) ? Frame(image: f.image, delay: f.delay * 2) : nil
            }
            let quantized = try await Quantize(colors: colors).process(optimizedFrames)
            data = try Encoder.encodeAPNG(frames: quantized, loopCount: loopCount)
        }

        return Result(
            data: data,
            format: .apng,
            size: size,
            fileSize: data.count,
            isWithinLimit: data.count <= StickerSize.maxFileSize
        )
    }
}
