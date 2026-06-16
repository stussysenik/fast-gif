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

                    // Start handle — contained to [0, end−minGap], frame-snapped.
                    TrimHandle(color: Theme.accent)
                        .offset(x: min(max(CGFloat(startFrac) * width - 8, 0), width - 16))
                        .gesture(DragGesture()
                            .onChanged { v in
                                guard project.videoDuration > 0, width > 0 else { return }
                                let t = snap(Double(min(max(v.location.x, 0), width) / width) * project.videoDuration)
                                project.trimStart = min(max(0, t), effectiveEnd - Self.minGap)
                            }
                            .onEnded { _ in onRetrim() }
                        )
                        .accessibilityLabel("Trim start")
                        .accessibilityValue(formatTime(project.trimStart))

                    // End handle — contained to [start+minGap, duration], frame-snapped.
                    TrimHandle(color: Theme.accent)
                        .offset(x: min(max(CGFloat(endFrac) * width - 8, 0), width - 16))
                        .gesture(DragGesture()
                            .onChanged { v in
                                guard project.videoDuration > 0, width > 0 else { return }
                                let t = snap(Double(min(max(v.location.x, 0), width) / width) * project.videoDuration)
                                project.trimEnd = max(project.trimStart + Self.minGap, min(t, project.videoDuration))
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

    /// Hard floor on selection length — handles cannot cross or collapse.
    private static let minGap: Double = 0.2
    /// Frame grid for snapping (import samples at 10 fps by default).
    private static let frameStep: Double = 0.1

    /// Snap a time to the nearest frame boundary.
    private func snap(_ t: Double) -> Double {
        (t / Self.frameStep).rounded() * Self.frameStep
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
        RoundedRectangle(cornerRadius: Theme.radiusSmall)
            .fill(color)
            .frame(width: 16, height: 36)
            .contentShape(Rectangle().inset(by: -14))
    }
}
