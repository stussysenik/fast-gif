import Foundation

/// A processing stage in the GIF pipeline.
/// Stages are composable, testable, and independently deployable.
protocol Stage {
    func process(_ frames: [Frame]) async throws -> [Frame]
}

/// Composes stages using Swift's @resultBuilder for declarative pipelines.
///
///     let p = Pipeline {
///         Resize(to: CGSize(width: 320, height: 240))
///         Quantize(colors: 256)
///         Dither(.floydSteinberg)
///     }
///     let output = try await p.run(inputFrames)
///
@resultBuilder
struct PipelineBuilder {
    static func buildExpression(_ stage: any Stage) -> [any Stage] { [stage] }
    static func buildBlock(_ stages: [any Stage]...) -> [any Stage] { stages.flatMap { $0 } }
    static func buildOptional(_ stage: [any Stage]?) -> [any Stage] { stage ?? [] }
    static func buildEither(first stages: [any Stage]) -> [any Stage] { stages }
    static func buildEither(second stages: [any Stage]) -> [any Stage] { stages }
    static func buildArray(_ stages: [[any Stage]]) -> [any Stage] { stages.flatMap { $0 } }
}

struct Pipeline {
    let stages: [any Stage]

    init(@PipelineBuilder _ build: () -> [any Stage]) {
        self.stages = build()
    }

    init(stages: [any Stage]) {
        self.stages = stages
    }

    /// Execute the pipeline — frames flow through each stage sequentially.
    func run(_ input: [Frame]) async throws -> [Frame] {
        var frames = input
        for stage in stages {
            try Task.checkCancellation()
            frames = try await stage.process(frames)
        }
        return frames
    }

    /// Run with progress reporting.
    func run(_ input: [Frame], progress: (Double) -> Void) async throws -> [Frame] {
        var frames = input
        let total = Double(stages.count)
        for (i, stage) in stages.enumerated() {
            try Task.checkCancellation()
            progress(Double(i) / total)
            frames = try await stage.process(frames)
        }
        progress(1.0)
        return frames
    }
}

/// Identity stage — passes frames through unchanged. Useful as a placeholder.
struct Passthrough: Stage {
    func process(_ frames: [Frame]) async throws -> [Frame] { frames }
}
