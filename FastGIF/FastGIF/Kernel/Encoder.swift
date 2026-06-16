import Foundation
import ImageIO
import AVFoundation
import CoreImage
import UniformTypeIdentifiers
import MobileCoreServices
import FastGIFCore

/// All supported export formats. WebP/HEIC were removed in the export-truth
/// change: their CGImageDestination paths silently dropped every frame but the
/// first, so they could not honestly carry an animation.
enum ExportFormat: String, CaseIterable, Identifiable {
    case gif, apng, mp4, mov

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .mp4: "MP4"
        case .mov: "MOV"
        }
    }

    var fileExtension: String { rawValue }
    var supportsTransparency: Bool { self != .mp4 && self != .mov }

    var uti: CFString {
        switch self {
        case .gif: kUTTypeGIF
        case .apng: "public.png" as CFString
        case .mp4: kUTTypeMPEG4
        case .mov: kUTTypeQuickTimeMovie
        }
    }
}

/// Encodes Frame arrays into various output formats.
/// GIF uses Rust NeuQuant engine for quality + speed.
enum Encoder {

    // MARK: - GIF (Rust NeuQuant)

    static func encodeGIF(frames: [Frame], loopCount: Int = 0, colors: Int = 256, quality: Int32 = 10) throws -> Data {
        guard !frames.isEmpty else { throw EncoderError.noFrames }

        // Convert CGImage frames to RGBA pixel buffers for Rust
        var rawFrames: [RawFrame] = []
        var pixelBuffers: [UnsafeMutablePointer<UInt8>] = []

        for frame in frames {
            let w = frame.image.width
            let h = frame.image.height
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
            guard let ctx = CGContext(
                data: buffer,
                width: w, height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                buffer.deallocate()
                continue
            }
            ctx.draw(frame.image, in: CGRect(x: 0, y: 0, width: w, height: h))

            rawFrames.append(RawFrame(
                rgba: UnsafePointer(buffer),
                width: UInt32(w),
                height: UInt32(h),
                delay_cs: UInt16(max(2, frame.delay * 100)) // seconds → centiseconds, min 20ms
            ))
            pixelBuffers.append(buffer)
        }
        defer { pixelBuffers.forEach { $0.deallocate() } }

        guard !rawFrames.isEmpty else { throw EncoderError.noFrames }

        guard let result = rawFrames.withUnsafeBufferPointer({ buf in
            fastgif_encode(
                buf.baseAddress,
                buf.count,
                UInt32(min(max(colors, 2), 256)),
                UInt16(loopCount),
                quality // NeuQuant sample factor: 1=best, 30=fastest.
            )
        }) else {
            throw EncoderError.finalizeFailed
        }
        defer { fastgif_free(result) }

        return Data(bytes: result.pointee.data, count: result.pointee.len)
    }

    // MARK: - APNG (iMessage sticker format)

    static func encodeAPNG(frames: [Frame], loopCount: Int = 0) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, frames.count, nil
        ) else { throw EncoderError.creationFailed }

        let pngProperties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: loopCount
            ]
        ]
        CGImageDestinationSetProperties(dest, pngProperties as CFDictionary)

        for frame in frames {
            autoreleasepool {
                let frameProps: [CFString: Any] = [
                    kCGImagePropertyPNGDictionary: [
                        kCGImagePropertyAPNGDelayTime: frame.delay
                    ]
                ]
                CGImageDestinationAddImage(dest, frame.image, frameProps as CFDictionary)
            }
        }

        guard CGImageDestinationFinalize(dest) else { throw EncoderError.finalizeFailed }
        return data as Data
    }

    // MARK: - MP4 / MOV (Hardware-accelerated)

    static func encodeVideo(
        frames: [Frame],
        format: ExportFormat,
        outputURL: URL
    ) async throws {
        guard !frames.isEmpty else { throw EncoderError.noFrames }
        let size = frames[0].size

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format == .mp4 ? .mp4 : .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var currentTime: Double = 0
        let context = CIContext(options: [.useSoftwareRenderer: false])

        for frame in frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            try Task.checkCancellation()

            try autoreleasepool {
                let ciImage = CIImage(cgImage: frame.image)
                guard let pool = adaptor.pixelBufferPool else { throw EncoderError.bufferPoolFailed }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard let buffer = pixelBuffer else { throw EncoderError.bufferCreationFailed }
                context.render(ciImage, to: buffer)

                let time = CMTime(seconds: currentTime, preferredTimescale: 600)
                adaptor.append(buffer, withPresentationTime: time)
                currentTime += frame.delay
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw writer.error ?? EncoderError.finalizeFailed
        }
    }

    // MARK: - Universal encode

    static func encode(
        frames: [Frame],
        format: ExportFormat,
        loopCount: Int = 0,
        colors: Int = 256,
        quality: Int32 = 10
    ) async throws -> Data {
        switch format {
        case .gif:
            return try encodeGIF(frames: frames, loopCount: loopCount, colors: colors, quality: quality)
        case .apng:
            return try encodeAPNG(frames: frames, loopCount: loopCount)
        case .mp4, .mov:
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(format.fileExtension)
            try await encodeVideo(frames: frames, format: format, outputURL: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return try Data(contentsOf: url)
        }
    }

    // MARK: - Preview (single-frame quantization, exact colors)

    /// Quantize one frame through the Rust preview FFI — the same NeuQuant path
    /// GIF export uses. Returns a palette-reconstructed frame so the preview
    /// shows the exact colors the export will ship. Returns the input unchanged
    /// on any failure. Given matching `colors`/`quality`, the resulting color set
    /// is identical to `encodeGIF`'s for that frame (witnessed by PreviewParityTests).
    static func previewFrame(_ frame: Frame, colors: Int, quality: Int32) -> Frame {
        let w = frame.image.width
        let h = frame.image.height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        defer { buffer.deallocate() }
        guard let ctx = CGContext(
            data: buffer,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return frame }
        ctx.draw(frame.image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let rf = fastgif_preview_frame(
            buffer, UInt32(w), UInt32(h),
            UInt32(min(max(colors, 2), 256)), quality
        ) else { return frame }
        defer { fastgif_raw_frame_free(rf) }

        let outData = Data(bytes: rf.pointee.rgba, count: w * h * 4)
        guard let provider = CGDataProvider(data: outData as CFData),
              let cg = CGImage(
                width: w, height: h,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return frame }
        return Frame(image: cg, delay: frame.delay)
    }
}

enum EncoderError: Error, LocalizedError {
    case creationFailed, finalizeFailed, noFrames
    case bufferPoolFailed, bufferCreationFailed, formatUnsupported

    var errorDescription: String? {
        switch self {
        case .creationFailed: "Couldn't create encoder"
        case .finalizeFailed: "Encoding failed"
        case .noFrames: "No frames to encode"
        case .bufferPoolFailed: "Pixel buffer pool unavailable"
        case .bufferCreationFailed: "Couldn't create pixel buffer"
        case .formatUnsupported: "Format not supported on this device"
        }
    }
}
