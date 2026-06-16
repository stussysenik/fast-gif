import SwiftUI

/// The heart of the app — WYSIWYG editor.
/// iA Writer principle: focused editing surface, controls reveal on demand.
struct EditorView: View {
    @Bindable var project: GIFProject
    @State private var showControls = false
    @State private var showExport = false
    @State private var showPalette = false
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            // WYSIWYG Preview — shows processed output
            AnimatedPreview(
                frames: project.previewFrames.isEmpty ? project.frames : project.previewFrames,
                isLoading: project.isImporting,
                loadingProgress: project.importProgress
            ) { time in
                project.currentTime = time
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .padding(Theme.spacing16)
            .onTapGesture { showControls.toggle() }

            // Trim bar — only when a video source is available
            if project.sourceVideoURL != nil {
                TrimView(project: project) {
                    project.scheduleRetrim()
                }
            }

            // Time ruler — replaces frame thumbnails
            TimeScrubber(project: project)
                .frame(height: 56)

            // Controls bar
            if showControls {
                ControlsBar(project: project)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.springSnappy, value: showControls)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export", systemImage: "square.and.arrow.up") {
                    showExport = true
                }
                .disabled(!project.hasFrames)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Filters", systemImage: "camera.filters") {
                    showFilters = true
                }
                .disabled(!project.hasFrames)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Palette", systemImage: "paintpalette") {
                    showPalette = true
                }
                .disabled(!project.hasFrames)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Controls", systemImage: "slider.horizontal.3") {
                    showControls.toggle()
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

                // Quality
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Quality").sectionHeader()
                    Picker("Quality", selection: $project.quality) {
                        ForEach(Quality.allCases) { q in
                            Text(q.displayName).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
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
