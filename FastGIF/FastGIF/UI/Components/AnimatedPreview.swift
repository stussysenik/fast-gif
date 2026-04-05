import SwiftUI

/// Animates through frames at their natural timing — the live preview.
struct AnimatedPreview: View {
    let frames: [Frame]
    @State private var currentIndex = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if let frame = frames[safe: currentIndex] {
                Image(decorative: frame.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ContentUnavailableView("No Frames", systemImage: "photo.stack")
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
        .onChange(of: frames.count) { startAnimation() }
    }

    private func startAnimation() {
        stopAnimation()
        guard frames.count > 1 else { return }
        currentIndex = 0
        scheduleNext()
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNext() {
        guard let frame = frames[safe: currentIndex] else { return }
        timer = Timer.scheduledTimer(withTimeInterval: frame.delay, repeats: false) { _ in
            currentIndex = (currentIndex + 1) % frames.count
            scheduleNext()
        }
    }
}

/// Progress overlay — shown during export/processing.
struct ProcessingOverlay: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: Theme.spacing16) {
            ProgressView(value: progress)
                .tint(Theme.accent)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .cardStyle()
        .frame(maxWidth: 200)
    }
}

// MARK: - Safe Array Access

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
