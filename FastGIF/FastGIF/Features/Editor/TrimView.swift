import SwiftUI
import AVFoundation

/// Video trim bar with draggable in/out handles.
struct TrimView: View {
    @Bindable var project: GIFProject
    let onRetrim: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing8) {
            HStack {
                Text("Trim").sectionHeader()
                Spacer()
                Text(timeLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.textSecondary)
            }

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Theme.surface)
                        .frame(height: 36)

                    // Selected range
                    let startFrac = project.videoDuration > 0 ? project.trimStart / project.videoDuration : 0
                    let endFrac = project.videoDuration > 0 ? effectiveEnd / project.videoDuration : 1

                    Capsule()
                        .fill(Theme.accent.opacity(0.3))
                        .frame(width: CGFloat(endFrac - startFrac) * width, height: 36)
                        .offset(x: CGFloat(startFrac) * width)

                    // Start handle
                    TrimHandle(color: Theme.accent)
                        .offset(x: CGFloat(startFrac) * width - 8)
                        .gesture(DragGesture()
                            .onChanged { v in
                                let frac = max(0, min(v.location.x / width, effectiveEnd / project.videoDuration - 0.01))
                                project.trimStart = frac * project.videoDuration
                            }
                            .onEnded { _ in onRetrim() }
                        )
                        .accessibilityLabel("Trim start")
                        .accessibilityValue(formatTime(project.trimStart))

                    // End handle
                    TrimHandle(color: Theme.accent)
                        .offset(x: CGFloat(endFrac) * width - 8)
                        .gesture(DragGesture()
                            .onChanged { v in
                                let frac = max(project.trimStart / project.videoDuration + 0.01, min(v.location.x / width, 1))
                                project.trimEnd = frac * project.videoDuration
                            }
                            .onEnded { _ in onRetrim() }
                        )
                        .accessibilityLabel("Trim end")
                        .accessibilityValue(formatTime(effectiveEnd))
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing8)
    }

    private var effectiveEnd: Double {
        project.trimEnd ?? project.videoDuration
    }

    private var timeLabel: String {
        let duration = effectiveEnd - project.trimStart
        return "\(formatTime(0)) – \(formatTime(duration))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return m > 0 ? String(format: "%d:%02d.%d", m, s, ms) : String(format: "%d.%ds", s, ms)
    }
}

/// Draggable handle for the trim bar.
struct TrimHandle: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 16, height: 44)
            .contentShape(Rectangle().inset(by: -10))
    }
}
