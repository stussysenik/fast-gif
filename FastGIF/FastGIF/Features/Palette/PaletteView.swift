import SwiftUI
import CoreImage

/// Color palette extraction and editing.
/// Extracts dominant colors from frames using Core Image's area histogram.
struct PaletteView: View {
    @Bindable var project: GIFProject
    @State private var extractedColors: [Color] = []
    @State private var isExtracting = false

    var body: some View {
        VStack(spacing: Theme.spacing16) {
            Text("Color Palette").sectionHeader()

            if extractedColors.isEmpty && !isExtracting {
                Button("Extract Colors", systemImage: "eyedropper") {
                    Task { await extractColors() }
                }
                .buttonStyle(.bordered)
            } else if isExtracting {
                ProgressView("Analyzing...")
            } else {
                // Color grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: Theme.spacing4) {
                    ForEach(Array(extractedColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(height: 32)
                    }
                }

                // Color count control
                HStack {
                    Text("Palette size")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("Colors", selection: $project.quantizeColors) {
                        Text("16").tag(16)
                        Text("32").tag(32)
                        Text("64").tag(64)
                        Text("128").tag(128)
                        Text("256").tag(256)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
        .cardStyle()
    }

    private func extractColors() async {
        isExtracting = true
        defer { isExtracting = false }

        guard let frame = project.frames.first else { return }
        let ciImage = CIImage(cgImage: frame.image)
        let context = CIContext()

        // Use K-means style extraction via posterize + sampling
        guard let posterized = CIFilter(name: "CIColorPosterize", parameters: [
            kCIInputImageKey: ciImage,
            "inputLevels": NSNumber(value: 6)
        ])?.outputImage,
              let cgImage = context.createCGImage(posterized, from: posterized.extent) else { return }

        // Sample pixels
        let width = cgImage.width
        let height = cgImage.height
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return }

        var colorSet = Set<UInt32>()
        let stride = cgImage.bytesPerRow
        let step = max(1, (width * height) / 64) // Sample ~64 points

        for i in Swift.stride(from: 0, to: width * height, by: step) {
            let x = i % width
            let y = i / width
            let offset = y * stride + x * 4
            let r = ptr[offset]
            let g = ptr[offset + 1]
            let b = ptr[offset + 2]
            // Quantize to reduce near-duplicates
            let qr = (r / 32) * 32
            let qg = (g / 32) * 32
            let qb = (b / 32) * 32
            colorSet.insert(UInt32(qr) << 16 | UInt32(qg) << 8 | UInt32(qb))
        }

        extractedColors = colorSet.prefix(32).map { packed in
            let r = Double((packed >> 16) & 0xFF) / 255
            let g = Double((packed >> 8) & 0xFF) / 255
            let b = Double(packed & 0xFF) / 255
            return Color(red: r, green: g, blue: b)
        }
    }
}
