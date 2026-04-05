import SwiftUI

/// iMessage Sticker export wizard — auto-optimizes to fit Apple's 500KB limit.
struct StickerWizardView: View {
    @Bindable var project: GIFProject
    @State private var stickerSize: StickerSize = .medium
    @State private var result: StickerOptimizer.Result?
    @State private var isOptimizing = false
    @State private var removeBackground = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing24) {
                // Preview
                if project.hasFrames {
                    AnimatedPreview(frames: project.frames)
                        .frame(width: 200, height: 200)
                        .background(
                            // Checker pattern for transparency
                            CheckerboardPattern()
                                .foregroundStyle(Color.gray.opacity(0.2))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }

                // Size picker
                VStack(spacing: Theme.spacing8) {
                    Text("Sticker Size").sectionHeader()
                    Picker("Size", selection: $stickerSize) {
                        ForEach(StickerSize.allCases) { size in
                            VStack {
                                Text(size.rawValue)
                                Text("\(Int(size.pixels.width))px")
                                    .font(.caption2)
                            }
                            .tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, Theme.spacing16)

                // Background removal toggle
                Toggle(isOn: $removeBackground) {
                    Label("Remove Background", systemImage: "person.crop.rectangle")
                }
                .padding(.horizontal, Theme.spacing16)

                // Result info
                if let result {
                    VStack(spacing: Theme.spacing8) {
                        HStack {
                            Text("File Size")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(result.fileSize), countStyle: .file))
                                .font(.body.monospaced())
                                .foregroundStyle(result.isWithinLimit ? Theme.success : Theme.destructive)
                        }
                        HStack {
                            Text("Limit")
                            Spacer()
                            Text("500 KB")
                                .font(.body.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if result.isWithinLimit {
                            Label("Ready for iMessage", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.success)
                        } else {
                            Label("Over size limit — try smaller size or fewer frames", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.destructive)
                                .font(.caption)
                        }
                    }
                    .cardStyle()
                    .padding(.horizontal, Theme.spacing16)
                }

                Spacer()

                // Optimize & Export
                Button {
                    Task { await optimize() }
                } label: {
                    HStack {
                        Spacer()
                        if isOptimizing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label(result == nil ? "Optimize" : "Export Sticker",
                                  systemImage: result == nil ? "wand.and.stars" : "square.and.arrow.up")
                        }
                        Spacer()
                    }
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOptimizing || !project.hasFrames)
                .padding(.horizontal, Theme.spacing16)
                .padding(.bottom, Theme.spacing16)
            }
            .navigationTitle("Sticker Wizard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func optimize() async {
        if let result {
            // Export
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("sticker")
                .appendingPathExtension("apng")
            try? result.data.write(to: tempURL)
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = windowScene.windows.first?.rootViewController {
                root.present(activityVC, animated: true)
            }
            return
        }

        isOptimizing = true
        defer { isOptimizing = false }

        var frames = project.frames
        if removeBackground {
            frames = (try? await RemoveBackground().process(frames)) ?? frames
        }

        result = try? await StickerOptimizer.optimize(
            frames: frames,
            size: stickerSize,
            loopCount: project.loopCount
        )
    }
}

/// Checkerboard pattern for showing transparency.
struct CheckerboardPattern: Shape {
    let size: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = Int(rect.height / size)
        let cols = Int(rect.width / size)
        for row in 0...rows {
            for col in 0...cols where (row + col).isMultiple(of: 2) {
                path.addRect(CGRect(
                    x: CGFloat(col) * size,
                    y: CGFloat(row) * size,
                    width: size, height: size
                ))
            }
        }
        return path
    }
}
