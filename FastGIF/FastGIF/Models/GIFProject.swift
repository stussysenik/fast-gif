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
    var quality: Quality = .best { didSet { schedulePreview() } }
    var speed: Double = 1.0 { didSet { schedulePreview() } }
    var loopCount: Int = 0
    var maxWidth: CGFloat? { didSet { schedulePreview() } }
    var backgroundRemoved = false
    var filterPreset: FilterPreset = .none { didSet { schedulePreview() } }
    var filterIntensity: Float = 1.0 { didSet { schedulePreview() } }

    /// User-facing notice surfaced after import (e.g. duration cap applied).
    var importNotice: String?

    /// Hard duration cap enforced at import. The frame-array RAM model can't hold
    /// unbounded clips; streaming is deferred to v1.1.
    static let maxImportDuration: Double = 15

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

    /// Resolution/sampling profile for the single shared pipeline.
    enum PipelineScale { case preview, export }

    /// The single source of truth for CPU-side processing. Preview and export run
    /// the *same* stages; they differ only in resolution (and the caller's frame
    /// sampling). Quantization + dithering for GIF are owned by the Rust encoder,
    /// not this pipeline — `BayerDither` is the one exception, applied for `.good`.
    func buildPipeline(scale: PipelineScale) -> Pipeline {
        let maxEdge: Int
        switch scale {
        case .preview:
            maxEdge = 240
        case .export:
            maxEdge = maxWidth.map { Int($0) }
                ?? document.frames.first.map { max($0.width, $0.height) }
                ?? 640
        }
        return Pipeline {
            AspectResize(maxEdge: maxEdge)
            if speed != 1.0 {
                Speed(multiplier: speed)
            }
            if let stage = filterPreset.toStage(intensity: filterIntensity) {
                stage
            }
            if quality.usesBayer {
                BayerDither(colors: quantizeColors)
            }
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
    /// Each sampled frame is run through the same Rust NeuQuant path as export
    /// (at the fast `draft` sample factor) so the preview shows true palette
    /// colors — not a posterize approximation.
    func updatePreview() async {
        guard hasFrames else { previewFrames = []; return }

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

        let pipeline = buildPipeline(scale: .preview)
        guard let processed = try? await pipeline.run(sampled) else { return }
        guard !Task.isCancelled else { return }

        // Reconstruct exact palette colors via the shared quantizer (fast factor
        // for responsiveness; the exact selected-quality still is C6's job).
        let colors = quantizeColors
        let factor = Quality.draft.sampleFactor
        let exact = processed.map { Encoder.previewFrame($0, colors: colors, quality: factor) }
        guard !Task.isCancelled else { return }
        previewFrames = exact
    }

    /// Process and export with current settings.
    func export() async throws -> Data {
        isProcessing = true
        progress = 0
        error = nil
        defer { isProcessing = false }

        do {
            let pipeline = buildPipeline(scale: .export)
            let frames = document.frames
            let fmt = exportFormat
            let loops = loopCount
            let colors = quantizeColors
            let factor = quality.sampleFactor
            let dither = quality.usesDiffusion
            let processed = try await pipeline.run(frames) { [weak self] p in
                Task { @MainActor in self?.progress = p * 0.8 }
            }
            progress = 0.8
            let data = try await Encoder.encode(
                frames: processed,
                format: fmt,
                loopCount: loops,
                colors: colors,
                quality: factor,
                dither: dither
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

        // Enforce the hard duration cap; surface the reason if we clamped.
        let requestedEnd = trimEnd ?? videoDuration
        let cappedEnd: Double
        if requestedEnd - trimStart > Self.maxImportDuration {
            cappedEnd = trimStart + Self.maxImportDuration
            importNotice = "Limited to the first \(Int(Self.maxImportDuration))s — long clips are capped to keep memory in check."
        } else {
            cappedEnd = requestedEnd
            importNotice = nil
        }

        let frames = try await Decoder.decodeVideo(
            url: url, fps: fps,
            startTime: trimStart,
            endTime: cappedEnd
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
        importNotice = nil
        currentTime = 0
    }
}
