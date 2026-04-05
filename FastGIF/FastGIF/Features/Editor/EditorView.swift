import SwiftUI

/// The heart of the app — frame editor with timeline.
/// iA Writer principle: focused editing surface, controls reveal on demand.
struct EditorView: View {
    @Bindable var project: GIFProject
    @State private var showControls = false
    @State private var showExport = false

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            AnimatedPreview(frames: project.frames)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .padding(Theme.spacing16)
                .onTapGesture { showControls.toggle() }

            // Timeline
            TimelineView(project: project)
                .frame(height: 80)

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
                Button("Controls", systemImage: "slider.horizontal.3") {
                    showControls.toggle()
                }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView(project: project)
        }
        .overlay {
            if project.isProcessing {
                ProcessingOverlay(
                    progress: project.progress,
                    message: "Processing..."
                )
            }
        }
    }
}

/// Horizontal scrolling frame timeline.
struct TimelineView: View {
    @Bindable var project: GIFProject

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: Theme.spacing4) {
                ForEach(Array(project.frames.enumerated()), id: \.element.id) { index, frame in
                    FrameThumbnail(
                        frame: frame,
                        isSelected: project.selectedFrameIndex == index,
                        index: index
                    )
                    .onTapGesture { project.selectedFrameIndex = index }
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            project.duplicateFrame(at: index)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            project.deleteFrame(at: index)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.spacing16)
        }
        .background(Theme.surface)
    }
}

struct FrameThumbnail: View {
    let frame: Frame
    let isSelected: Bool
    let index: Int

    var body: some View {
        VStack(spacing: Theme.spacing2) {
            Image(decorative: frame.image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
                )

            Text("\(Int(frame.delay * 1000))ms")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
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
                    Text("\(project.speed, specifier: "%.1f")x")
                        .font(.caption2.monospaced())
                }

                Divider().frame(height: 40)

                // Colors
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    Text("Colors").sectionHeader()
                    Picker("", selection: $project.quantizeColors) {
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
                    Picker("", selection: $project.ditherAlgorithm) {
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
