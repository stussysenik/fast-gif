import Foundation
import ImageIO
import AVFoundation
import CoreImage
import UniformTypeIdentifiers
import MobileCoreServices

/// All supported export formats.
enum ExportFormat: String, CaseIterable, Identifiable {
    case gif, apng, webp, mp4, mov, heic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gif: "GIF"
        case .apng: "APNG"
        case .webp: "WebP"
        case .mp4: "MP4"
        case .mov: "MOV"
        case .heic: "HEIC"
        }
    }

    var fileExtension: String { rawValue }
    var supportsTransparency: Bool { self != .mp4 && self != .mov }

    var uti: CFString {
        switch self {
        case .gif: kUTTypeGIF
        case .apng: "public.png" as CFString
        case .webp: "org.webmproject.webp" as CFString
        case .mp4: kUTTypeMPEG4
        case .mov: kUTTypeQuickTimeMovie
        case .heic: "public.heic" as CFString
        }
    }
}

/// Encodes Frame arrays into various output formats.
enum Encoder {

    // MARK: - GIF

    static func encodeGIF(frames: [Frame], loopCount: Int = 0) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, kUTTypeGIF, frames.count, nil
        ) else { throw EncoderError.creationFailed }

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        for frame in frames {
            let frameProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.delay
                ]
            ]
            CGImageDestinationAddImage(dest, frame.image, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(dest) else { throw EncoderError.finalizeFailed }
        return data as Data
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
            let frameProps: [CFString: Any] = [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: frame.delay
                ]
            ]
            CGImageDestinationAddImage(dest, frame.image, frameProps as CFDictionary)
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
        loopCount: Int = 0
    ) async throws -> Data {
        switch format {
        case .gif:
            return try encodeGIF(frames: frames, loopCount: loopCount)
        case .apng:
            return try encodeAPNG(frames: frames, loopCount: loopCount)
        case .mp4, .mov:
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(format.fileExtension)
            try await encodeVideo(frames: frames, format: format, outputURL: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return try Data(contentsOf: url)
        case .webp, .heic:
            // WebP/HEIC animated: use CGImageDestination if available
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(
                data, format.uti, frames.count, nil
            ) else { throw EncoderError.formatUnsupported }
            for frame in frames {
                CGImageDestinationAddImage(dest, frame.image, nil)
            }
            guard CGImageDestinationFinalize(dest) else { throw EncoderError.finalizeFailed }
            return data as Data
        }
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
