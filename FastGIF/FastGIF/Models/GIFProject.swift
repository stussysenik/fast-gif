import SwiftUI
import Foundation
import Observation

/// The single source of truth for the entire app.
/// iA Writer philosophy: one document, one focus.
@Observable
final class GIFProject {
    var document = GIFDocument()
    var selectedFrameIndex: Int?
    var exportFormat: ExportFormat = .gif
    var isProcessing = false
    var progress: Double = 0
    var error: String?

    // Pipeline config — power user controls
    var quantizeColors: Int = 256
    var ditherAlgorithm: DitherAlgorithm = .floydSteinberg
    var ditherStrength: Float = 1.0
    var speed: Double = 1.0
    var loopCount: Int = 0 // 0 = infinite
    var maxWidth: CGFloat?
    var backgroundRemoved = false

    // Computed
    var frames: [Frame] { document.frames }
    var hasFrames: Bool { !document.frames.isEmpty }
    var selectedFrame: Frame? {
        guard let i = selectedFrameIndex, document.frames.indices.contains(i) else { return nil }
        return document.frames[i]
    }

    /// Build the processing pipeline from current settings.
    func buildPipeline() -> Pipeline {
        Pipeline {
            if let maxWidth {
                Resize(targetSize: CGSize(width: maxWidth, height: maxWidth))
            }
            if speed != 1.0 {
                Speed(multiplier: speed)
            }
            Quantize(colors: quantizeColors)
            Dither(ditherAlgorithm, strength: ditherStrength)
        }
    }

    /// Process and export with current settings.
    func export() async throws -> Data {
        isProcessing = true
        progress = 0
        error = nil
        defer { isProcessing = false }

        do {
            let pipeline = buildPipeline()
            let processed = try await pipeline.run(document.frames) { [weak self] p in
                Task { @MainActor in self?.progress = p * 0.8 }
            }
            progress = 0.8
            let data = try await Encoder.encode(
                frames: processed,
                format: exportFormat,
                loopCount: loopCount
            )
            progress = 1.0
            return data
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Import from video URL.
    func importVideo(url: URL, fps: Double = 10) async throws {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        let frames = try await Decoder.decodeVideo(url: url, fps: fps)
        document = GIFDocument(frames: frames, loopCount: loopCount)
        selectedFrameIndex = 0
    }

    /// Import from image data (GIF, APNG, static image).
    func importImageData(_ data: Data) throws {
        let frames = try Decoder.decodeImageSource(from: data)
        document = GIFDocument(frames: frames, loopCount: loopCount)
        selectedFrameIndex = 0
    }

    /// Add frames from images.
    func addFrames(_ images: [CGImage], delay: TimeInterval = 0.1) {
        let newFrames = images.map { Frame(image: $0, delay: delay) }
        document.frames.append(contentsOf: newFrames)
        if selectedFrameIndex == nil { selectedFrameIndex = 0 }
    }

    func deleteFrame(at index: Int) {
        guard document.frames.indices.contains(index) else { return }
        document.frames.remove(at: index)
        if let sel = selectedFrameIndex, sel >= document.frames.count {
            selectedFrameIndex = document.frames.isEmpty ? nil : document.frames.count - 1
        }
    }

    func moveFrame(from source: IndexSet, to destination: Int) {
        document.frames.move(fromOffsets: source, toOffset: destination)
    }

    func duplicateFrame(at index: Int) {
        guard document.frames.indices.contains(index) else { return }
        let frame = document.frames[index]
        let copy = Frame(image: frame.image, delay: frame.delay)
        document.frames.insert(copy, at: index + 1)
    }

    func reverseFrames() {
        document.frames.reverse()
    }

    func reset() {
        document = GIFDocument()
        selectedFrameIndex = nil
        isProcessing = false
        progress = 0
        error = nil
    }
}
