import SwiftUI

/// Multi-format export with size comparison — one tap, all formats.
struct ExportView: View {
    @Bindable var project: GIFProject
    @State private var exportedData: Data?
    @State private var exportResults: [(ExportFormat, Int)] = []
    @State private var showShareSheet = false
    @State private var showStickerWizard = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Format picker
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        HStack {
                            Label(format.displayName, systemImage: iconForFormat(format))
                            Spacer()
                            if let size = exportResults.first(where: { $0.0 == format })?.1 {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if project.exportFormat == format {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { project.exportFormat = format }
                    }
                } header: {
                    Text("Format")
                }

                // Settings
                Section {
                    Stepper("Loop: \(project.loopCount == 0 ? "∞" : "\(project.loopCount)")",
                            value: $project.loopCount, in: 0...100)

                    if let width = project.frames.first?.width {
                        HStack {
                            Text("Max Width")
                            Spacer()
                            Text("\(project.maxWidth.map { "\(Int($0))px" } ?? "\(width)px (original)")")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    Text("Settings")
                }

                // iMessage Stickers
                Section {
                    Button {
                        showStickerWizard = true
                    } label: {
                        Label("iMessage Sticker Wizard", systemImage: "message.badge.waveform")
                    }
                } header: {
                    Text("Stickers")
                }

                // Export button
                Section {
                    Button {
                        Task { await exportAndShare() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Export \(project.exportFormat.displayName)",
                                  systemImage: "square.and.arrow.up")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(project.isProcessing || !project.hasFrames)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showStickerWizard) {
                StickerWizardView(project: project)
            }
            .task { await estimateSizes() }
        }
    }

    private func estimateSizes() async {
        guard project.hasFrames else { return }
        let pipeline = project.buildPipeline()
        guard let processed = try? await pipeline.run(project.frames) else { return }

        // Estimate the currently selected format first so the UI is responsive immediately.
        let selected = project.exportFormat
        if let data = try? await Encoder.encode(frames: processed, format: selected) {
            exportResults.append((selected, data.count))
        }

        // Lazily estimate the remaining formats in the background.
        for format in ExportFormat.allCases where format != selected {
            if let data = try? await Encoder.encode(frames: processed, format: format) {
                exportResults.append((format, data.count))
            }
        }
    }

    private func exportAndShare() async {
        guard let data = try? await project.export() else { return }
        exportedData = data

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FastGIF-export")
            .appendingPathExtension(project.exportFormat.fileExtension)
        try? data.write(to: tempURL)

        // Share via UIActivityViewController — must present on the main thread.
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        await MainActor.run {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(activityVC, animated: true)
            }
        }
    }

    private func iconForFormat(_ format: ExportFormat) -> String {
        switch format {
        case .gif: "play.rectangle"
        case .apng: "photo.stack"
        case .webp: "globe"
        case .mp4, .mov: "film"
        case .heic: "square.stack.3d.up"
        }
    }
}
