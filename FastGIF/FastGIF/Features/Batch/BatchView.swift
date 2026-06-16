import SwiftUI
import UniformTypeIdentifiers

/// Batch processing — convert many files with saved presets.
/// The #1 missing feature in every iOS GIF app.
struct BatchView: View {
    @Bindable var project: GIFProject
    @State private var inputURLs: [URL] = []
    @State private var results: [BatchResult] = []
    @State private var isProcessing = false
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                } header: {
                    Text("Input (\(inputURLs.count) files)")
                }

                if !inputURLs.isEmpty {
                    Section {
                        ForEach(inputURLs, id: \.absoluteString) { url in
                            Label(url.lastPathComponent, systemImage: "doc")
                        }
                        .onDelete { indexSet in
                            inputURLs.remove(atOffsets: indexSet)
                        }
                    }

                    Section {
                        HStack {
                            Text("Format")
                            Spacer()
                            Picker("", selection: $project.exportFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                        }
                        HStack {
                            Text("Colors")
                            Spacer()
                            Picker("", selection: $project.quantizeColors) {
                                Text("16").tag(16)
                                Text("64").tag(64)
                                Text("128").tag(128)
                                Text("256").tag(256)
                            }
                        }
                    } header: {
                        Text("Settings")
                    }

                    Section {
                        Button {
                            Task { await processAll() }
                        } label: {
                            HStack {
                                Spacer()
                                Label(isProcessing ? "Processing..." : "Process All",
                                      systemImage: "bolt.fill")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }
                }

                if !results.isEmpty {
                    Section {
                        ForEach(results) { result in
                            HStack {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.success ? Theme.success : Theme.destructive)
                                Text(result.filename)
                                Spacer()
                                if let size = result.outputSize {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    } header: {
                        Text("Results")
                    }
                }
            }
            .navigationTitle("Batch")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.gif, .png, .movie, .video, .mpeg4Movie],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    inputURLs.append(contentsOf: urls)
                }
            }
        }
    }

    private func processAll() async {
        isProcessing = true
        results = []

        let pipeline = project.buildPipeline(scale: .export)
        let format = project.exportFormat
        let loopCount = project.loopCount
        let colors = project.quantizeColors
        let factor = project.quality.sampleFactor
        let dither = project.quality.usesDiffusion

        for url in inputURLs {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let frames: [Frame]
                if url.pathExtension.lowercased() == "gif" || url.pathExtension.lowercased() == "png" {
                    let data = try Data(contentsOf: url)
                    frames = try Decoder.decodeImageSource(from: data)
                } else {
                    frames = try await Decoder.decodeVideo(url: url)
                }

                let processed = try await pipeline.run(frames)
                let data = try await Encoder.encode(frames: processed, format: format, loopCount: loopCount, colors: colors, quality: factor, dither: dither)

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension(format.fileExtension)
                try data.write(to: outputURL)

                results.append(BatchResult(filename: url.lastPathComponent, success: true, outputSize: data.count))
            } catch {
                results.append(BatchResult(filename: url.lastPathComponent, success: false, error: error.localizedDescription))
            }
        }
        isProcessing = false
    }
}

struct BatchResult: Identifiable {
    let id = UUID()
    let filename: String
    let success: Bool
    var outputSize: Int?
    var error: String?
}
