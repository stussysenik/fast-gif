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
    /// Sub-frame ms-precision toggle. Persisted across launches so power
    /// users keep the mode they want without re-toggling each session.
    @AppStorage("editor.msPrecision") private var msPrecision: Bool = false
    @State private var grab: Grab?
    @State private var model: TimelineModel = .empty

    /// Which handle is currently being dragged + where it started.
    /// In integer mode `anchorFrame` is the integer frame of the handle.
    /// In ms mode `anchorSeconds` holds the precise time so we don't lose
    /// sub-frame precision on each drag tick.
    private struct Grab: Equatable {
        enum Handle { case start, end, playhead }
        let handle: Handle
        let anchorFrame: Int
        let anchorSeconds: Double
    }

    var body: some View {
        VStack(spacing: Theme.spacing8) {
            header
            GeometryReader { geo in
                rail(width: geo.size.width)
            }
            .frame(height: railTotalHeight)
            footer
            #if DEBUG
            debugStrip
            #endif
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
            Text(formatTime(model.trimStartSecondsPrecise))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Text("—")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(formatTime(model.trimEndSecondsPrecise))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Spacer()
            Text(formatTime(model.playheadSecondsPrecise))
                .font(.callout.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.tap, value: model.playheadSecondsPrecise)
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
                let anchorFrame = grab?.anchorFrame ?? currentFrame(for: handle)
                let anchorSeconds = grab?.anchorSeconds ?? currentSeconds(for: handle)
                if grab == nil {
                    grab = Grab(handle: handle, anchorFrame: anchorFrame, anchorSeconds: anchorSeconds)
                }
                let target = targetSeconds(fromAnchorSeconds: anchorSeconds,
                                           pixelDelta: value.translation.width,
                                           railWidth: railWidth)
                applyTarget(handle: handle, targetSeconds: target)
            }
            .onEnded { value in
                // Velocity continuity: apply predicted residual with spring.
                let predicted = value.predictedEndTranslation.width
                let settled = value.translation.width
                let residual = predicted - settled
                let anchorSeconds = grab?.anchorSeconds ?? currentSeconds(for: handle)
                withAnimation(reduceMotion ? nil : Motion.flick) {
                    let target = targetSeconds(fromAnchorSeconds: anchorSeconds,
                                               pixelDelta: predicted,
                                               railWidth: railWidth)
                    applyTarget(handle: handle, targetSeconds: target)
                }
                grab = nil
                if abs(residual) < 1 || handle != .playhead {
                    onTrimCommit()
                }
            }
    }

    /// Position-aware conversion of a pixel drag translation to a target
    /// time in source seconds. Uses the current `TimelineGeometry` so the
    /// math is warp-correct: the anchor is first mapped to its x-coordinate
    /// under the current geometry, the drag `dx` is added in rail space,
    /// and the inverse geometry map produces the new source time.
    ///
    /// For linear geometry (warp == nil) this collapses to the old formula
    /// `anchorSeconds + dx/W × duration`. For warped geometry, the inverse
    /// map correctly accounts for local focus scale so a handle in the
    /// focus zone moves by the visual distance under the finger, not by
    /// the unwarped linear distance.
    private func targetSeconds(fromAnchorSeconds anchor: Double,
                               pixelDelta dx: CGFloat,
                               railWidth: CGFloat) -> Double {
        let geo = model.geometry
        let anchorX = geo.xPosition(forSeconds: anchor, railWidth: railWidth)
        return geo.seconds(forX: anchorX + dx, railWidth: railWidth)
    }

    /// Apply a target time to the right handle via the model, choosing the
    /// precise or integer mutator based on `msPrecision`. Centralises the
    /// precise-vs-integer branch that used to live inline in the gesture.
    private func applyTarget(handle: Grab.Handle, targetSeconds: Double) {
        if msPrecision {
            applyPrecise(handle: handle, targetSeconds: targetSeconds)
        } else {
            let targetFrame = Int((targetSeconds * Double(model.fps)).rounded())
            apply(handle: handle, target: targetFrame)
        }
    }

    private func currentSeconds(for handle: Grab.Handle) -> Double {
        switch handle {
        case .start: return model.trimStartSecondsPrecise
        case .end: return model.trimEndSecondsPrecise
        case .playhead: return model.playheadSecondsPrecise
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

    private func applyPrecise(handle: Grab.Handle, targetSeconds: Double) {
        var m = model
        switch handle {
        case .start:
            m.moveTrimStartPrecise(toSeconds: targetSeconds)
            project.trimStart = m.trimStartSecondsPrecise
        case .end:
            m.moveTrimEndPrecise(toSeconds: targetSeconds)
            project.trimEnd = m.trimEndSecondsPrecise
        case .playhead:
            m.movePlayheadPrecise(toSeconds: targetSeconds)
            project.currentTime = m.playheadSecondsPrecise
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
        if msPrecision {
            // 0.000s style — full ms precision so the user can dial frames
            // by ear. Switches to mm:ss.mmm past 60s.
            let whole = Int(clamped)
            let ms = Int(((clamped - Double(whole)) * 1000).rounded())
            if whole >= 60 {
                let m = whole / 60
                let s = whole % 60
                return String(format: "%d:%02d.%03d", m, s, ms)
            }
            return String(format: "%d.%03ds", whole, ms)
        }
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

    // MARK: - Debug strip

    #if DEBUG
    /// Always-visible state strip in DEBUG builds. Surfaces the exact
    /// frame/seconds values that feed into the geometry + fisheye warp
    /// math, so we can verify Slice 4's behavior visually without
    /// spelunking through logs. Stripped from Release builds.
    @ViewBuilder
    private var debugStrip: some View {
        let geo = model.geometry
        let window = model.trimWindowSeconds
        let minDelta = model.minNeighborDeltaSeconds
        VStack(alignment: .leading, spacing: 1) {
            debugRow(label: "start", frame: model.trimStartFrame, seconds: model.trimStartSecondsPrecise)
            debugRow(label: " end ", frame: model.trimEndFrame, seconds: model.trimEndSecondsPrecise)
            debugRow(label: "head ", frame: model.playheadFrame, seconds: model.playheadSecondsPrecise)
            Text(String(format: "trim: %.3fs  min Δ: %.3fs", window, minDelta))
            if let warp = geo.warp {
                Text(String(format: "warp: amount=%.2f  scale=%.1f×", warp.amount, warp.scale))
                Text(String(format: "      focus=[%.3fs, %.3fs]", warp.focus.lowerBound, warp.focus.upperBound))
            } else {
                Text("warp: linear")
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func debugRow(label: String, frame: Int, seconds: Double) -> some View {
        Text(String(format: "%@  f=%04d  t=%7.4fs", label, frame, seconds))
    }
    #endif

    // MARK: - Project bridge

    private func refreshModel() {
        guard var built = TimelineModel.make(from: project) else { return }
        // Carry sub-frame ms-precision state across rebuilds without firing
        // haptics. The precise mutators would re-fire detent tokens on each
        // refresh; restorePreciseFractions skips that.
        let endSeconds = project.trimEnd ?? built.trimEndSeconds
        built.restorePreciseFractions(
            playheadSeconds: project.currentTime,
            trimStartSeconds: project.trimStart,
            trimEndSeconds: endSeconds
        )
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
