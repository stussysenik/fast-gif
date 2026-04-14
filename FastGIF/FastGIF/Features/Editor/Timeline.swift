import SwiftUI

/// Unified timeline editor — trim handles + playhead on one rail.
///
/// Replaces the pair of `TrimView` + `TimeScrubber` with a single frame-accurate
/// control. Internal state lives in a pure `TimelineModel` value type so the
/// math is tested independently of SwiftUI.
///
/// Four detent classes fire haptic feedback via `.sensoryFeedback(_:trigger:)`:
///   - Frame step → `.selection` (one per frame dragged)
///   - Whole-second crossing → `.alignment` (soft "you're at a second")
///   - Endpoint (frame 0 / last) → `.impact(flexibility: .rigid)`
///   - Playhead crosses trim boundary → `.impact(flexibility: .soft)`
///
/// Grab-to-magnify: on touch-down the active handle scales from rest size to
/// 1.5x using `Motion.tap`. Tap target stays ≥44pt at all times via inset
/// `contentShape`, even when the visual rest size is smaller.
///
/// Velocity continuity: drag-end uses `DragGesture.Value.predictedEndTranslation`
/// to compute residual frame offset, then applies it with `Motion.flick` so the
/// handle lands with natural inertia — iMovie's behavior.
///
/// Accessibility: three separate `.accessibilityElement`s for start, playhead,
/// and end, each with a frame-stepping `.accessibilityAdjustableAction`. The
/// magnification animation is gated on `accessibilityReduceMotion`.
struct Timeline: View {
    @Bindable var project: GIFProject
    let onTrimCommit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grab: Grab?
    @State private var model: TimelineModel = .empty

    /// Which handle is currently being dragged + where it started, in frames.
    private struct Grab: Equatable {
        enum Handle { case start, end, playhead }
        let handle: Handle
        let anchorFrame: Int
    }

    var body: some View {
        VStack(spacing: Theme.spacing8) {
            header
            GeometryReader { geo in
                rail(width: geo.size.width)
            }
            .frame(height: railTotalHeight)
            footer
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .onAppear(perform: refreshModel)
        .onChange(of: project.frames.count) { refreshModel() }
        .onChange(of: project.videoDuration) { refreshModel() }
        .onChange(of: project.currentTime) { newValue in
            // External playback position updates (AnimatedPreview tick) —
            // only adopt if no drag in progress, to avoid fighting the user.
            guard grab == nil else { return }
            let frame = model.frameFromSeconds(newValue)
            if frame != model.playheadFrame {
                var m = model
                m.movePlayhead(to: frame)
                model = m
            }
        }
        // Haptic wiring — one modifier per detent class. The trigger value is
        // a monotonic token on the model; when it changes, the haptic fires.
        .sensoryFeedback(.selection, trigger: model.frameStepToken)
        .sensoryFeedback(.alignment, trigger: model.secondDetentToken)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: model.endpointDetentToken)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.trimCrossingToken)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(formatTime(model.trimStartSeconds))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Text("—")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(formatTime(model.trimEndSeconds))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Spacer()
            Text(formatTime(model.playheadSeconds))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.tap, value: model.playheadFrame)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Rail

    /// Vertical extent of the rail region (track + handle overhang).
    private let railTotalHeight: CGFloat = 56
    /// Height of the track bar itself.
    private let trackHeight: CGFloat = 8
    /// Rest size of trim handles.
    private let handleRestSize = CGSize(width: 14, height: 44)
    /// Grab-magnify scale factor.
    private let grabScale: CGFloat = 1.45
    /// Playhead circle size.
    private let playheadSize: CGFloat = 18

    private func rail(width railWidth: CGFloat) -> some View {
        let startX = model.xPosition(for: model.trimStartFrame, railWidth: railWidth)
        let endX = model.xPosition(for: model.trimEndFrame, railWidth: railWidth)
        let headX = model.xPosition(for: model.playheadFrame, railWidth: railWidth)

        return ZStack(alignment: .leading) {
            // Base track
            Capsule()
                .fill(Theme.surface)
                .frame(height: trackHeight)
                .frame(maxHeight: .infinity)

            // Selected (trimmed) band
            Capsule()
                .fill(Theme.accent.opacity(0.22))
                .frame(width: max(0, endX - startX), height: trackHeight)
                .offset(x: startX)
                .frame(maxHeight: .infinity)

            // Start handle
            trimHandle(at: startX, isGrabbed: grab?.handle == .start, axis: .leading)
                .gesture(trimDragGesture(for: .start, railWidth: railWidth))
                .accessibilityElement()
                .accessibilityLabel("Trim start")
                .accessibilityValue(formatTime(model.trimStartSeconds))
                .accessibilityAdjustableAction { direction in
                    stepTrimStart(direction)
                }

            // End handle
            trimHandle(at: endX, isGrabbed: grab?.handle == .end, axis: .trailing)
                .gesture(trimDragGesture(for: .end, railWidth: railWidth))
                .accessibilityElement()
                .accessibilityLabel("Trim end")
                .accessibilityValue(formatTime(model.trimEndSeconds))
                .accessibilityAdjustableAction { direction in
                    stepTrimEnd(direction)
                }

            // Playhead
            playhead(at: headX, isGrabbed: grab?.handle == .playhead)
                .gesture(playheadDragGesture(railWidth: railWidth))
                .accessibilityElement()
                .accessibilityLabel("Playhead")
                .accessibilityValue(formatTime(model.playheadSeconds))
                .accessibilityAdjustableAction { direction in
                    stepPlayhead(direction)
                }
        }
    }

    private func trimHandle(at x: CGFloat, isGrabbed: Bool, axis: HorizontalAlignment) -> some View {
        let scale = isGrabbed ? grabScale : 1.0
        let halfWidth = handleRestSize.width / 2
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.accent)
            .frame(width: handleRestSize.width, height: handleRestSize.height)
            .overlay(
                // Tactile grip indicator — two subtle lines
                VStack(spacing: 3) {
                    Capsule().fill(.white.opacity(0.7)).frame(width: 2, height: 10)
                    Capsule().fill(.white.opacity(0.7)).frame(width: 2, height: 10)
                }
            )
            .scaleEffect(scale, anchor: .center)
            .animation(reduceMotion ? nil : Motion.tap, value: isGrabbed)
            .shadow(color: .black.opacity(isGrabbed ? 0.18 : 0.08),
                    radius: isGrabbed ? 6 : 2, y: 1)
            .offset(x: x - halfWidth)
            // Tap target ≥44×44pt regardless of visual size.
            .contentShape(Rectangle().inset(by: -14))
    }

    private func playhead(at x: CGFloat, isGrabbed: Bool) -> some View {
        let scale = isGrabbed ? grabScale : 1.0
        let half = playheadSize / 2
        return ZStack {
            Circle()
                .fill(Theme.background)
                .frame(width: playheadSize + 4, height: playheadSize + 4)
            Circle()
                .fill(Theme.accent)
                .frame(width: playheadSize, height: playheadSize)
        }
        .scaleEffect(scale)
        .animation(reduceMotion ? nil : Motion.tap, value: isGrabbed)
        .shadow(color: Theme.accent.opacity(0.35), radius: isGrabbed ? 8 : 4)
        .offset(x: x - half - 2)
        .contentShape(Rectangle().inset(by: -14))
    }

    // MARK: - Gestures

    private func trimDragGesture(for handle: Grab.Handle, railWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let anchor = grab?.anchorFrame ?? currentFrame(for: handle)
                if grab == nil {
                    grab = Grab(handle: handle, anchorFrame: anchor)
                }
                let delta = model.frameDelta(forPixelDelta: value.translation.width, railWidth: railWidth)
                apply(handle: handle, target: anchor + delta)
            }
            .onEnded { value in
                // Velocity continuity: apply predicted residual with spring.
                let predicted = value.predictedEndTranslation.width
                let settled = value.translation.width
                let residual = predicted - settled
                let anchor = grab?.anchorFrame ?? currentFrame(for: handle)
                let totalDelta = model.frameDelta(forPixelDelta: predicted, railWidth: railWidth)
                let target = anchor + totalDelta
                withAnimation(reduceMotion ? nil : Motion.flick) {
                    apply(handle: handle, target: target)
                }
                grab = nil
                if abs(residual) < 1 || handle != .playhead {
                    onTrimCommit()
                }
            }
    }

    private func playheadDragGesture(railWidth: CGFloat) -> some Gesture {
        trimDragGesture(for: .playhead, railWidth: railWidth)
    }

    private func currentFrame(for handle: Grab.Handle) -> Int {
        switch handle {
        case .start: return model.trimStartFrame
        case .end: return model.trimEndFrame
        case .playhead: return model.playheadFrame
        }
    }

    private func apply(handle: Grab.Handle, target: Int) {
        var m = model
        switch handle {
        case .start:
            m.moveTrimStart(to: target)
            project.trimStart = m.trimStartSeconds
        case .end:
            m.moveTrimEnd(to: target)
            project.trimEnd = m.trimEndSeconds
        case .playhead:
            m.movePlayhead(to: target)
            project.currentTime = m.playheadSeconds
        }
        model = m
    }

    // MARK: - Accessibility actions

    private func stepTrimStart(_ direction: AccessibilityAdjustmentDirection) {
        let step = direction == .increment ? 1 : -1
        var m = model
        m.moveTrimStart(to: m.trimStartFrame + step)
        project.trimStart = m.trimStartSeconds
        model = m
        onTrimCommit()
    }

    private func stepTrimEnd(_ direction: AccessibilityAdjustmentDirection) {
        let step = direction == .increment ? 1 : -1
        var m = model
        m.moveTrimEnd(to: m.trimEndFrame + step)
        project.trimEnd = m.trimEndSeconds
        model = m
        onTrimCommit()
    }

    private func stepPlayhead(_ direction: AccessibilityAdjustmentDirection) {
        let step = direction == .increment ? 1 : -1
        var m = model
        m.movePlayhead(to: m.playheadFrame + step)
        project.currentTime = m.playheadSeconds
        model = m
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(model.trimmedFrameCount) frames")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(formatDuration(model.trimmedDuration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let whole = Int(clamped)
        let tenths = Int((clamped - Double(whole)) * 10)
        if whole >= 60 {
            let m = whole / 60
            let s = whole % 60
            return String(format: "%d:%02d.%d", m, s, tenths)
        }
        return String(format: "%d.%ds", whole, tenths)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        return String(format: "%.2fs", clamped)
    }

    // MARK: - Project bridge

    private func refreshModel() {
        guard let built = TimelineModel.make(from: project) else { return }
        model = built
    }
}

// MARK: - Model helpers

private extension TimelineModel {
    static var empty: TimelineModel {
        TimelineModel(totalFrames: 2, fps: 24)
    }

    /// Inclusive frame count in the trimmed range.
    var trimmedFrameCount: Int { trimEndFrame - trimStartFrame + 1 }

    func frameFromSeconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * Double(fps)).rounded())
    }

    /// Build a model from the live `GIFProject`, deriving fps from frame count
    /// and total duration. Returns nil if the project has no frames yet.
    static func make(from project: GIFProject) -> TimelineModel? {
        let count = project.frames.count
        guard count >= 2 else { return nil }
        let duration = project.videoDuration > 0
            ? project.videoDuration
            : project.frames.reduce(0.0) { $0 + $1.delay }
        guard duration > 0 else { return nil }
        let fps = max(1, Int((Double(count - 1) / duration).rounded()))
        let start = Int((project.trimStart * Double(fps)).rounded())
        let end = Int(((project.trimEnd ?? duration) * Double(fps)).rounded())
        let head = Int((project.currentTime * Double(fps)).rounded())
        return TimelineModel(
            totalFrames: count,
            fps: fps,
            trimStartFrame: start,
            trimEndFrame: end,
            playheadFrame: head
        )
    }
}
