import SwiftUI
import Foundation
import Observation
import AVFoundation

/// The single source of truth for the entire app.
/// iA Writer philosophy: one document, one focus.
@MainActor @Observable
final class GIFProject {
    var document = GIFDocument()
    var selectedFrameIndex: Int?
    var exportFormat: ExportFormat = .gif
    var isProcessing = false
    var isImporting = false
    var importProgress: Double = 0
    var progress: Double = 0
    var error: String?

    // Trim state
    var trimStart: Double = 0
    var trimEnd: Double?
    var videoDuration: Double = 0
    var sourceVideoURL: URL?

    // Pipeline config
    var quantizeColors: Int = 256 { didSet { schedulePreview() } }
    var ditherAlgorithm: DitherAlgorithm = .floydSteinberg { didSet { schedulePreview() } }
    var ditherStrength: Float = 1.0 { didSet { schedulePreview() } }
    var speed: Double = 1.0 { didSet { schedulePreview() } }
    var loopCount: Int = 0
    var maxWidth: CGFloat? { didSet { schedulePreview() } }
    var backgroundRemoved = false
    var filterPreset: FilterPreset = .none { didSet { schedulePreview() } }
    var filterIntensity: Float = 1.0 { didSet { schedulePreview() } }

    // WYSIWYG preview — processed frames at preview resolution
    var previewFrames: [Frame] = []
    private var previewTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var retrimTask: Task<Void, Never>?

    // Computed
    var frames: [Frame] { document.frames }
    var hasFrames: Bool { !document.frames.isEmpty }
    var currentTime: Double = 0
    var totalDuration: Double { document.duration }

    /// Build the processing pipeline from current settings.
    func buildPipeline() -> Pipeline {
        Pipeline {
            if let maxWidth {
                Resize(targetSize: CGSize(width: maxWidth, height: maxWidth))
            }
            if speed != 1.0 {
                Speed(multiplier: speed)
            }
            if let stage = filterPreset.toStage(intensity: filterIntensity) {
                stage
            }
            Quantize(colors: quantizeColors)
            Dither(ditherAlgorithm, strength: ditherStrength)
        }
    }

    /// Schedule a debounced preview update (300ms).
    func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.updatePreview()
        }
    }

    /// Process frames at preview resolution for WYSIWYG.
    /// Samples max ~30 frames from the full set for fast preview generation.
    func updatePreview() async {
        guard hasFrames else { previewFrames = []; return }

        let previewSize: CGFloat = 240
        let allFrames = document.frames
        // Sample evenly — 30 frames is plenty for a 240px preview
        let maxPreview = 30
        let sampled: [Frame]
        if allFrames.count <= maxPreview {
            sampled = allFrames
        } else {
            let step = Double(allFrames.count) / Double(maxPreview)
            sampled = (0..<maxPreview).map { i in
                allFrames[min(Int(Double(i) * step), allFrames.count - 1)]
            }
        }

        let pipeline = Pipeline {
            Resize(targetSize: CGSize(width: previewSize, height: previewSize))
            if speed != 1.0 {
                Speed(multiplier: speed)
            }
            if let stage = filterPreset.toStage(intensity: filterIntensity) {
                stage
            }
            Quantize(colors: quantizeColors)
        }

        if let processed = try? await pipeline.run(sampled) {
            guard !Task.isCancelled else { return }
            previewFrames = processed
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
            let frames = document.frames
            let fmt = exportFormat
            let loops = loopCount
            let processed = try await pipeline.run(frames) { [weak self] p in
                Task { @MainActor in self?.progress = p * 0.8 }
            }
            progress = 0.8
            let data = try await Encoder.encode(
                frames: processed,
                format: fmt,
                loopCount: loops
            )
            progress = 1.0
            return data
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Import from video URL, applying current trim range.
    func importVideo(url: URL, fps: Double = 10) async throws {
        isImporting = true
        importProgress = 0
        error = nil
        defer { isImporting = false }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        videoDuration = CMTimeGetSeconds(duration)
        sourceVideoURL = url

        let frames = try await Decoder.decodeVideo(
            url: url, fps: fps,
            startTime: trimStart,
            endTime: trimEnd ?? videoDuration
        ) { [weak self] p in
            Task { @MainActor [weak self] in self?.importProgress = p }
        }
        document = GIFDocument(frames: frames, loopCount: loopCount)
        selectedFrameIndex = 0
        await updatePreview()
    }

    /// Debounced retrim — waits 600ms after last call, cancels in-flight imports.
    func scheduleRetrim() {
        retrimTask?.cancel()
        importTask?.cancel()
        retrimTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard let self, let url = self.sourceVideoURL else { return }
            self.importTask = Task {
                try? await self.importVideo(url: url)
            }
        }
    }

    func importImageData(_ data: Data) throws {
        let frames = try Decoder.decodeImageSource(from: data)
        document = GIFDocument(frames: frames, loopCount: loopCount)
        selectedFrameIndex = 0
        schedulePreview()
    }

    func addFrames(_ images: [CGImage], delay: TimeInterval = 0.1) {
        let newFrames = images.map { Frame(image: $0, delay: delay) }
        document.frames.append(contentsOf: newFrames)
        if selectedFrameIndex == nil { selectedFrameIndex = 0 }
        schedulePreview()
    }

    func deleteFrame(at index: Int) {
        guard document.frames.indices.contains(index) else { return }
        document.frames.remove(at: index)
        if let sel = selectedFrameIndex, sel >= document.frames.count {
            selectedFrameIndex = document.frames.isEmpty ? nil : document.frames.count - 1
        }
        schedulePreview()
    }

    func moveFrame(from source: IndexSet, to destination: Int) {
        document.frames.move(fromOffsets: source, toOffset: destination)
    }

    func duplicateFrame(at index: Int) {
        guard document.frames.indices.contains(index) else { return }
        let frame = document.frames[index]
        document.frames.insert(Frame(image: frame.image, delay: frame.delay), at: index + 1)
        schedulePreview()
    }

    func reverseFrames() {
        document.frames.reverse()
        schedulePreview()
    }

    func updateFrameDelay(at index: Int, delay: Double) {
        guard document.frames.indices.contains(index) else { return }
        document.frames[index].delay = delay
    }

    func reset() {
        previewTask?.cancel()
        importTask?.cancel()
        retrimTask?.cancel()
        document = GIFDocument()
        previewFrames = []
        selectedFrameIndex = nil
        isProcessing = false
        isImporting = false
        importProgress = 0
        progress = 0
        error = nil
        currentTime = 0
    }
}
