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

/// Quantize colors — reduce palette for GIF encoding.
struct Quantize: Stage {
    let colors: Int

    init(colors: Int = 256) {
        self.colors = min(max(colors, 2), 256)
    }

    func process(_ frames: [Frame]) async throws -> [Frame] {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let levels = NSNumber(value: max(2, Int(log2(Double(colors)))))
        var result = [Frame]()
        result.reserveCapacity(frames.count)
        for frame in frames {
            let processed: Frame = autoreleasepool {
                let ci = CIImage(cgImage: frame.image)
                guard let filter = CIFilter(name: "CIColorPosterize") else { return frame }
                filter.setValue(ci, forKey: kCIInputImageKey)
                filter.setValue(levels, forKey: "inputLevels")
                guard let output = filter.outputImage,
                      let cgImage = context.createCGImage(output, from: output.extent) else { return frame }
                return Frame(image: cgImage, delay: frame.delay)
            }
            result.append(processed)
            await Task.yield()
        }
        return result
    }
}

/// Dithering algorithms for reducing color banding.
enum DitherAlgorithm: String, CaseIterable, Identifiable {
    case floydSteinberg = "Floyd-Steinberg"
    case ordered = "Ordered"
    case bayer = "Bayer"
    case none = "None"

    var id: String { rawValue }
}

struct Dither: Stage {
    let algorithm: DitherAlgorithm
    let strength: Float

    init(_ algorithm: DitherAlgorithm = .floydSteinberg, strength: Float = 1.0) {
        self.algorithm = algorithm
        self.strength = strength
    }

    func process(_ frames: [Frame]) async throws -> [Frame] {
        guard algorithm != .none else { return frames }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let s = strength
        var result = [Frame]()
        result.reserveCapacity(frames.count)
        for frame in frames {
            let processed: Frame = autoreleasepool {
                let ci = CIImage(cgImage: frame.image)
                guard let noise = CIFilter(name: "CIRandomGenerator"),
                      let noiseOutput = noise.outputImage else { return frame }
                let noiseImage = noiseOutput
                    .cropped(to: ci.extent)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: CGFloat(s * 0.05), y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: CGFloat(s * 0.05), z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(s * 0.05), w: 0)
                    ])
                let dithered = ci.applyingFilter("CIAdditionCompositing", parameters: [
                    kCIInputBackgroundImageKey: noiseImage
                ])
                guard let cgImage = context.createCGImage(dithered, from: dithered.extent) else { return frame }
                return Frame(image: cgImage, delay: frame.delay)
            }
            result.append(processed)
            await Task.yield()
        }
        return result
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
