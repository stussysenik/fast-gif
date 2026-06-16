import SwiftUI
import PhotosUI
import UIKit

/// The entry point — import from camera roll, video, or files.
struct ImportView: View {
    @Bindable var project: GIFProject
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: Theme.spacing24) {
            Spacer()

            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Theme.textTertiary)

            Text("Create something")
                .font(.title2.weight(.medium))

            VStack(spacing: Theme.spacing12) {
                // Video import
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 1,
                    matching: .videos
                ) {
                    Label("From Video", systemImage: "video")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                // Image sequence import
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 50,
                    matching: .images
                ) {
                    Label("From Photos", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // File import (GIF, APNG)
                Button {
                    showFilePicker = true
                } label: {
                    Label("Open File", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 280)

            if let notice = project.importNotice {
                Label(notice, systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .transition(.opacity)
            }

            Spacer()
        }
        .animation(.easeInOut, value: project.importNotice)
        .onChange(of: selectedItems) {
            Task { await handleSelection(selectedItems) }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.gif, .png, .movie, .video, .mpeg4Movie],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleFileImport(result) }
        }
    }

    private func handleSelection(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }

        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            // Video
            if let data = try? await item.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mp4")
                try? data.write(to: tempURL)
                try? await project.importVideo(url: tempURL)
            }
        } else {
            // Images
            var images: [CGImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let cgImage = uiImage.cgImage {
                    images.append(cgImage)
                }
            }
            if !images.isEmpty {
                project.addFrames(images)
            }
        }
        selectedItems = []
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        if url.pathExtension.lowercased() == "gif" || url.pathExtension.lowercased() == "png" {
            if let data = try? Data(contentsOf: url) {
                try? project.importImageData(data)
            }
        } else {
            try? await project.importVideo(url: url)
        }
    }
}
