import SwiftUI
import Photos

/// Multi-format export — save to Photos or share.
struct ExportView: View {
    @Bindable var project: GIFProject
    @State private var estimatedSize: Int?
    @State private var showStickerWizard = false
    @State private var exportError: String?
    @State private var exportSuccess = false
    @State private var shareItem: ShareItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportFormat.allCases) { format in
                        HStack {
                            Label(format.displayName, systemImage: iconForFormat(format))
                            Spacer()
                            if format == project.exportFormat, let size = estimatedSize {
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
                        .onTapGesture {
                            project.exportFormat = format
                            estimatedSize = nil
                        }
                    }
                } header: {
                    Text("Format")
                }

                Section {
                    Stepper("Loop: \(project.loopCount == 0 ? "\u{221E}" : "\(project.loopCount)")",
                            value: $project.loopCount, in: 0...100)
                } header: {
                    Text("Settings")
                }

                Section {
                    Button { showStickerWizard = true } label: {
                        Label("iMessage Sticker Wizard", systemImage: "message.badge.waveform")
                    }
                } header: {
                    Text("Stickers")
                }

                if let exportError {
                    Section {
                        Label(exportError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.destructive)
                            .font(.caption)
                    }
                }

                if exportSuccess {
                    Section {
                        Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    }
                }

                // Primary: Save to Photos
                Section {
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        HStack {
                            Spacer()
                            if project.isProcessing {
                                ProgressView(value: project.progress)
                                    .frame(width: 120)
                                Text("\(Int(project.progress * 100))%")
                                    .font(.caption.monospaced())
                            } else {
                                Label("Save to Photos",
                                      systemImage: "photo.on.rectangle.angled")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(project.isProcessing || !project.hasFrames)

                    // Secondary: Share
                    Button {
                        Task { await exportAndShare() }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Share \(project.exportFormat.displayName)",
                                  systemImage: "square.and.arrow.up")
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
            .sheet(item: $shareItem) { item in
                ActivityView(url: item.url)
            }
            .task(id: project.exportFormat) { await estimateSize() }
        }
    }

    private func estimateSize() async {
        guard project.hasFrames else { return }
        estimatedSize = nil
        let pipeline = project.buildPipeline(scale: .export)
        let frames = project.frames
        let fmt = project.exportFormat
        let colors = project.quantizeColors
        let factor = project.quality.sampleFactor
        let dither = project.quality.usesDiffusion
        guard let processed = try? await pipeline.run(frames) else { return }
        if let data = try? await Encoder.encode(frames: processed, format: fmt, colors: colors, quality: factor, dither: dither) {
            estimatedSize = data.count
        }
    }

    private func saveToPhotos() async {
        exportError = nil
        exportSuccess = false
        do {
            let data = try await project.export()
            let ext = project.exportFormat.fileExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                exportError = "Photo library access denied. Enable in Settings."
                return
            }

            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let resourceType: PHAssetResourceType =
                    (project.exportFormat == .mp4 || project.exportFormat == .mov) ? .video : .photo
                request.addResource(with: resourceType, fileURL: tempURL, options: nil)
            }
            exportSuccess = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportAndShare() async {
        exportError = nil
        do {
            let data = try await project.export()
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FastGIF-\(UUID().uuidString)")
                .appendingPathExtension(project.exportFormat.fileExtension)
            try data.write(to: tempURL)
            shareItem = ShareItem(url: tempURL)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func iconForFormat(_ format: ExportFormat) -> String {
        switch format {
        case .gif: "play.rectangle"
        case .apng: "photo.stack"
        case .mp4, .mov: "film"
        }
    }
}

/// Identifiable wrapper for share sheet item (unique ID per export).
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet wrapper.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
