import Foundation
import CoreGraphics
import Accelerate
import CoreImage

// MARK: - Pipeline Stages

/// Resize frames using vImage (SIMD-accelerated).
struct Resize: Stage {
    let targetSize: CGSize

    func process(_ frames: [Frame]) async throws -> [Frame] {
        var result = [Frame]()
        result.reserveCapacity(frames.count)
        for frame in frames {
            let resized: CGImage? = autoreleasepool {
                resize(frame.image, to: targetSize)
            }
            guard let resized else { throw ProcessingError.resizeFailed }
            result.append(Frame(image: resized, delay: frame.delay))
            await Task.yield()
        }
        return result
    }

    private func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ) else { return nil }

        guard var sourceBuffer = try? vImage_Buffer(cgImage: image, format: format) else {
            return nil
        }
        defer { sourceBuffer.data?.deallocate() }

        guard var destBuffer = try? vImage_Buffer(
            width: Int(size.width),
            height: Int(size.height),
            bitsPerPixel: 32
        ) else { return nil }
        defer { destBuffer.data?.deallocate() }

        let error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }

        return try? destBuffer.createCGImage(format: format)
    }
}

/// Resize fitting the long edge to `maxEdge`, preserving the source aspect ratio.
/// Never upscales. This is the aspect-correct replacement for the old square
/// `Resize(maxWidth × maxWidth)` used by both preview and export.
struct AspectResize: Stage {
    let maxEdge: Int

    func process(_ frames: [Frame]) async throws -> [Frame] {
        guard let first = frames.first else { return [] }
        let srcW = first.width
        let srcH = first.height
        let longEdge = max(srcW, srcH)
        let scale = longEdge > maxEdge ? Double(maxEdge) / Double(longEdge) : 1.0
        let targetW = max(1, Int((Double(srcW) * scale).rounded()))
        let targetH = max(1, Int((Double(srcH) * scale).rounded()))
        return try await Resize(targetSize: CGSize(width: targetW, height: targetH)).process(frames)
    }
}

/// Output quality preset. Replaces the old (placebo) dither-algorithm picker.
/// Maps to the Rust encoder's NeuQuant sample factor and, for `.good`, an
/// ordered Bayer dither applied on the GPU before quantization.
enum Quality: String, CaseIterable, Identifiable {
    case draft, good, best

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .good: "Good"
        case .best: "Best"
        }
    }

    /// NeuQuant sample factor passed across the FFI: 1 = best/slowest, 30 = fastest.
    var sampleFactor: Int32 {
        switch self {
        case .draft: 30
        case .good: 10
        case .best: 1
        }
    }

    /// `.good` applies an 8×8 ordered Bayer dither (GPU) before quantization.
    var usesBayer: Bool { self == .good }

    /// `.best` applies deterministic spatial Sierra2_4a diffusion in the Rust
    /// encoder (`good` already dithered on the GPU; `draft` is nearest-color).
    var usesDiffusion: Bool { self == .best }
}

/// 8×8 ordered (Bayer) dither, applied on the GPU before quantization.
/// Used only by `Quality.good`. Adds a deterministic, position-dependent
/// threshold pattern so flat regions break into a stable stipple instead of
/// banding once the palette is reduced. Unlike the deleted `Dither` stage this
/// is real (no RNG) and reproducible.
struct BayerDither: Stage {
    let colors: Int

    init(colors: Int) {
        self.colors = min(max(colors, 2), 256)
    }

    /// Recursive 8×8 Bayer matrix, normalized to [0, 1).
    private static let matrix: [Float] = {
        let base: [[Int]] = [
            [ 0, 32,  8, 40,  2, 34, 10, 42],
            [48, 16, 56, 24, 50, 18, 58, 26],
            [12, 44,  4, 36, 14, 46,  6, 38],
            [60, 28, 52, 20, 62, 30, 54, 22],
            [ 3, 35, 11, 43,  1, 33,  9, 41],
            [51, 19, 59, 27, 49, 17, 57, 25],
            [15, 47,  7, 39, 13, 45,  5, 37],
            [63, 31, 55, 23, 61, 29, 53, 21]
        ]
        return base.flatMap { $0 }.map { (Float($0) + 0.5) / 64.0 }
    }()

    func process(_ frames: [Frame]) async throws -> [Frame] {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let tile = Self.makeTileImage() else { return frames }
        // Amplitude ≈ one quantization step per channel. NeuQuant builds a 3-D
        // palette, so per-channel resolution ≈ cbrt(colors) levels.
        let levels = max(2.0, pow(Double(colors), 1.0 / 3.0))
        let amplitude = CGFloat(1.0 / levels)

        var result = [Frame]()
        result.reserveCapacity(frames.count)
        for frame in frames {
            let processed: Frame = autoreleasepool {
                let ci = CIImage(cgImage: frame.image)
                // offset = (tile − 0.5) · amplitude, tiled across the frame.
                let offset = tile
                    .applyingFilter("CIAffineTile", parameters: [
                        kCIInputTransformKey: CGAffineTransform.identity
                    ])
                    .cropped(to: ci.extent)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: amplitude, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: amplitude, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: amplitude, w: 0),
                        "inputBiasVector": CIVector(x: -amplitude / 2, y: -amplitude / 2, z: -amplitude / 2, w: 0)
                    ])
                let dithered = ci.applyingFilter("CIAdditionCompositing", parameters: [
                    kCIInputBackgroundImageKey: offset
                ])
                guard let cgImage = context.createCGImage(dithered, from: ci.extent) else { return frame }
                return Frame(image: cgImage, delay: frame.delay)
            }
            result.append(processed)
            await Task.yield()
        }
        return result
    }

    /// Build the 8×8 Bayer threshold texture as a CIImage (grayscale, 0..1).
    private static func makeTileImage() -> CIImage? {
        let n = 8
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let v = UInt8((matrix[i] * 255).rounded())
            bytes[i * 4] = v
            bytes[i * 4 + 1] = v
            bytes[i * 4 + 2] = v
            bytes[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(
                width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return CIImage(cgImage: cg)
    }
}

/// Apply a Core Image filter chain — GPU-accelerated.
struct FilterStage: Stage {
    let filters: [(name: String, params: [String: Any])]

    func process(_ frames: [Frame]) async throws -> [Frame] {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        var result = [Frame]()
        result.reserveCapacity(frames.count)
        for frame in frames {
            let processed: Frame? = autoreleasepool {
                var ci = CIImage(cgImage: frame.image)
                for f in filters {
                    ci = ci.applyingFilter(f.name, parameters: f.params)
                }
                guard let cgImage = context.createCGImage(ci, from: ci.extent) else { return nil }
                return Frame(image: cgImage, delay: frame.delay)
            }
            if let processed { result.append(processed) }
            await Task.yield()
        }
        return result
    }
}

/// Crop frames to a region.
struct Crop: Stage {
    let rect: CGRect

    func process(_ frames: [Frame]) async throws -> [Frame] {
        frames.compactMap { frame in
            guard let cropped = frame.image.cropping(to: rect) else { return nil }
            return Frame(image: cropped, delay: frame.delay)
        }
    }
}

/// Reverse frame order for boomerang effect.
struct Reverse: Stage {
    func process(_ frames: [Frame]) async throws -> [Frame] {
        Array(frames.reversed())
    }
}

/// Adjust speed by modifying frame delays.
struct Speed: Stage {
    let multiplier: Double

    func process(_ frames: [Frame]) async throws -> [Frame] {
        frames.map { Frame(image: $0.image, delay: $0.delay / multiplier) }
    }
}

enum ProcessingError: Error, LocalizedError {
    case resizeFailed

    var errorDescription: String? {
        switch self {
        case .resizeFailed: "Resize failed"
        }
    }
}
