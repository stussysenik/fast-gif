import SwiftUI

/// The heart of the app — WYSIWYG editor.
/// iA Writer principle: focused editing surface, controls reveal on demand.
struct EditorView: View {
    @Bindable var project: GIFProject
    @State private var showControls = false
    @State private var showExport = false
    @State private var showPalette = false
    @State private var showFilters = false
    @State private var showSettings = false
    /// Anchors hardware-keyboard focus so spacebar reaches the editor.
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            // WYSIWYG Preview — shows processed output, restricted to the
            // current trim window so dragging the handles updates the live
            // preview immediately even before the WYSIWYG pass catches up.
            AnimatedPreview(
                frames: project.previewFrames.isEmpty ? project.trimmedFrames : project.previewFrames,
                isPlaying: project.isPlaying,
                isLoading: project.isImporting,
                loadingProgress: project.importProgress,
                speedMultiplier: project.speed
            ) { time in
                project.currentTime = time
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .padding(Theme.spacing16)
            .overlay(alignment: .bottomTrailing) {
                if project.hasFrames {
                    PlayPauseButton(isPlaying: project.isPlaying) {
                        project.isPlaying.toggle()
                    }
                    .padding(Theme.spacing16 + Theme.spacing8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Tap-to-toggle playback — the standard video gesture.
                // Controls live in the toolbar, so the preview is free
                // to behave like a media surface.
                guard project.hasFrames else { return }
                project.isPlaying.toggle()
            }

            // Unified timeline — trim handles + playhead on one rail.
            // Frame-accurate, detent haptics, velocity continuity, accessible.
            if project.hasFrames {
                Timeline(project: project) {
                    project.scheduleRetrim()
                }
            }

            // Controls bar
            if showControls {
                ControlsBar(project: project)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.springSnappy, value: showControls)
        .animation(Theme.springSnappy, value: project.isPlaying)
        // Hardware keyboard: spacebar toggles playback (iMovie convention).
        // Focusable on the whole editor surface; focus claimed onAppear.
        .focusable()
        .focused($keyboardFocus)
        .onAppear { keyboardFocus = true }
        .onKeyPress(.space) {
            guard project.hasFrames else { return .ignored }
            project.isPlaying.toggle()
            return .handled
        }
        .toolbar {
            // Primary action stays in the top bar — Export is the
            // single most important moment of the editing flow.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export", systemImage: "square.and.arrow.up") {
                    showExport = true
                }
                .disabled(!project.hasFrames)
            }
            // Everything else collapses into one More menu so the bar
            // isn't a wall of icons. Order matches frequency-of-use
            // (most common first).
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Controls", systemImage: "slider.horizontal.3") {
                        showControls.toggle()
                    }
                    Button("Filters", systemImage: "camera.filters") {
                        showFilters = true
                    }
                    .disabled(!project.hasFrames)
                    Button("Palette", systemImage: "paintpalette") {
                        showPalette = true
                    }
                    .disabled(!project.hasFrames)
                    Divider()
                    Button("Settings", systemImage: "gearshape") {
                        showSettings = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                        .accessibilityIdentifier("more.circle")
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(project: project)
        }
        .sheet(isPresented: $showPalette) {
            PaletteView(project: project)
        }
        .sheet(isPresented: $showFilters) {
            FilterView(project: project)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay {
            if project.isProcessing {
                ProcessingOverlay(
                    progress: project.progress,
                    message: "Processing\u{2026}"
                )
            }
        }
    }
}

/// Frosted circular play/pause button overlaid on the preview.
/// Matches Apple Photos / iMovie shape — 44pt tap target, soft shadow,
/// SF Symbol crossfade on toggle.
struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")
    }
}

/// Time-based scrubber — precise time ruler with current position.
/// Replaces frame thumbnails for a cleaner, more intuitive interface.
struct TimeScrubber: View {
    @Bindable var project: GIFProject

    var body: some View {
        VStack(spacing: Theme.spacing4) {
            // Time display
            HStack {
                Text(formatTime(project.currentTime))
                    .font(.system(size: 13, design: .monospaced).weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(project.frames.count) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(formatTime(project.totalDuration))
                    .font(.system(size: 13, design: .monospaced).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.spacing16)

            // Scrub bar
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = project.totalDuration > 0
                    ? project.currentTime / project.totalDuration
                    : 0

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Theme.surface)
                        .frame(height: 6)

                    // Progress
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(6, CGFloat(fraction) * width), height: 6)

                    // Playhead
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                        .shadow(color: Theme.accent.opacity(0.3), radius: 4)
                        .offset(x: CGFloat(fraction) * (width - 14))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let frac = max(0, min(value.location.x / width, 1))
                            project.currentTime = frac * project.totalDuration
                        }
                )
            }
            .frame(height: 14)
            .padding(.horizontal, Theme.spacing16)
        }
        .padding(.vertical, Theme.spacing8)
        .background(Theme.surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(formatTime(project.currentTime)) of \(formatTime(project.totalDuration))")
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return s >= 60
            ? String(format: "%d:%02d.%d", s / 60, s % 60, ms)
            : String(format: "%d.%ds", s, ms)
    }
}

/// Power user controls — progressive disclosure.
struct ControlsBar: View {
    @Bindable var project: GIFProject

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spacing16) {
                // Speed
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Speed").sectionHeader()
                    Slider(value: $project.speed, in: 0.1...5.0)
                        .frame(width: 120)
                        .accessibilityLabel("Playback speed")
                        .accessibilityValue("\(project.speed, specifier: "%.1f")x")
                    Text("\(project.speed, specifier: "%.1f")x")
                        .font(.caption2.monospaced())
                }

                Divider().frame(height: 40)

                // Colors
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Colors").sectionHeader()
                    Picker("Color count", selection: $project.quantizeColors) {
                        Text("16").tag(16)
                        Text("32").tag(32)
                        Text("64").tag(64)
                        Text("128").tag(128)
                        Text("256").tag(256)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Divider().frame(height: 40)

                // Dither
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Dither").sectionHeader()
                    Picker("Dither algorithm", selection: $project.ditherAlgorithm) {
                        ForEach(DitherAlgorithm.allCases) { algo in
                            Text(algo.rawValue).tag(algo)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().frame(height: 40)

                // Quick actions
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Actions").sectionHeader()
                    HStack(spacing: Theme.spacing8) {
                        Button("Reverse", systemImage: "arrow.left.arrow.right") {
                            project.reverseFrames()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(Theme.spacing16)
        }
        .background(Theme.surface)
    }
}
