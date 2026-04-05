import Foundation
import CoreGraphics
import ImageIO

/// The atom of FastGIF — a single animation frame.
struct Frame: Identifiable {
    let id = UUID()
    var image: CGImage
    var delay: Double

    init(image: CGImage, delay: Double = 0.1) {
        self.image = image
        self.delay = delay
    }

    var width: Int { image.width }
    var height: Int { image.height }
    var size: CGSize { CGSize(width: width, height: height) }
}

/// Lightweight project container — the document model.
struct GIFDocument {
    var frames: [Frame]
    var loopCount: Int

    init(frames: [Frame] = [], loopCount: Int = 0) {
        self.frames = frames
        self.loopCount = loopCount
    }

    var duration: Double {
        var total: Double = 0
        for f in frames { total += f.delay }
        return total
    }
    var frameCount: Int { frames.count }
}
