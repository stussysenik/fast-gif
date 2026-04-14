import SwiftUI

/// Animates through frames at their natural timing — the live preview.
/// Shows WYSIWYG processed frames when available, raw frames otherwise.
///
/// Playback is gated by `isPlaying` — when false, the timer is invalidated
/// and `currentIndex` freezes. Toggling true resumes from the held frame.
struct AnimatedPreview: View {
    let frames: [Frame]
    var isPlaying: Bool = true
    var isLoading = false
    var loadingProgress: Double = 0
    /// WYSIWYG speed multiplier. Each frame's per-frame `delay` is divided
    /// by this at schedule time, so changing speed is instantaneous and
    /// never triggers a pipeline re-run. Defaults to 1.0 for callers
    /// (e.g. StickerWizardView) that don't expose a speed control.
    var speedMultiplier: Double = 1.0
    var onTimeUpdate: ((Double) -> Void)?
    @State private var currentIndex = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if let frame = frames[safe: currentIndex] {
                Image(decorative: frame.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel("Preview, frame \(currentIndex + 1) of \(frames.count)")
            } else if isLoading {
                VStack(spacing: Theme.spacing16) {
                    ProgressView(value: loadingProgress)
                        .tint(Theme.accent)
                        .frame(maxWidth: 160)
                    Text("Importing\u{2026}")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                ContentUnavailableView("No Frames", systemImage: "photo.stack")
            }
        }
        .onAppear { syncPlayback() }
        .onDisappear { stopAnimation() }
        .onChange(of: frames.count) { startAnimation() }
        .onChange(of: isPlaying) { syncPlayback() }
        // Speed changes cancel the in-flight timer and reschedule at the
        // new rate. Without this, the timer closure captures the old
        // multiplier and the slider lags by up to one frame's interval.
        .onChange(of: speedMultiplier) { syncPlayback() }
    }

    private func syncPlayback() {
        if isPlaying {
            // Resume from current frame instead of restarting from 0,
            // so pause/play feels like freeze-frame, not rewind.
            stopAnimation()
            guard frames.count > 1 else { return }
            scheduleNext()
        } else {
            stopAnimation()
        }
    }

    private func startAnimation() {
        stopAnimation()
        guard frames.count > 1 else { return }
        currentIndex = 0
        if isPlaying { scheduleNext() }
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNext() {
        guard isPlaying, let frame = frames[safe: currentIndex] else { return }
        // Divide by speedMultiplier (floored at 0.1 to avoid pathological
        // intervals near zero). Export pipeline still applies Speed.
        let interval = frame.delay / max(0.1, speedMultiplier)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                guard isPlaying else { return }
                currentIndex = (currentIndex + 1) % frames.count
                // Report elapsed time in *source* seconds so the timeline
                // playhead tracks real trim coordinates, not speed-scaled ones.
                let elapsed = frames.prefix(currentIndex).reduce(0.0) { $0 + $1.delay }
                onTimeUpdate?(elapsed)
                scheduleNext()
            }
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
