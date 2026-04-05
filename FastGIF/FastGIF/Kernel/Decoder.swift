import Foundation
import AVFoundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers

/// Decodes various sources into Frame arrays.
enum Decoder {

    // MARK: - GIF / APNG / Image Sequence

    static func decodeImageSource(from data: Data) throws -> [Frame] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DecoderError.invalidData
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw DecoderError.noFrames }

        return (0..<count).compactMap { i -> Frame? in
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifProps = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let apngProps = props?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let gifDelay = (gifProps?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifProps?[kCGImagePropertyGIFDelayTime] as? Double)
            let apngDelay = (apngProps?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double)
                ?? (apngProps?[kCGImagePropertyAPNGDelayTime] as? Double)
            let delay = gifDelay ?? apngDelay ?? 0.1
            return Frame(image: image, delay: max(delay, 0.02))
        }
    }

    // MARK: - Video (Hardware-accelerated via AVFoundation)

    static func decodeVideo(url: URL, fps: Double = 10) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let track = try await asset.loadTracks(withMediaType: .video).first
        guard let track else { throw DecoderError.noVideoTrack }

        let size = try await track.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        let frameDuration = 1.0 / fps
        let totalSeconds = CMTimeGetSeconds(duration)
        var frames: [Frame] = []
        var nextTime: Double = 0

        while let buffer = output.copyNextSampleBuffer() {
            let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            guard time >= nextTime else { continue }
            nextTime = time + frameDuration

            if let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext(options: [.useSoftwareRenderer: false])
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    frames.append(Frame(image: cgImage, delay: frameDuration))
                }
            }
            try Task.checkCancellation()
        }

        guard !frames.isEmpty else { throw DecoderError.noFrames }
        return frames
    }

    // MARK: - Single Image

    static func decodeImage(data: Data) throws -> Frame {
        let frames = try decodeImageSource(from: data)
        guard let first = frames.first else { throw DecoderError.noFrames }
        return first
    }
}

enum DecoderError: Error, LocalizedError {
    case invalidData, noFrames, noVideoTrack

    var errorDescription: String? {
        switch self {
        case .invalidData: "Couldn't read this file"
        case .noFrames: "No frames found"
        case .noVideoTrack: "No video track found"
        }
    }
}
