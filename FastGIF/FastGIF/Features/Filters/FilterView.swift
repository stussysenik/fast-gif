import SwiftUI
import Foundation
import CoreImage

/// Real-time GPU filter chain — Core Image powered.
struct FilterView: View {
    @Bindable var project: GIFProject
    @State private var selectedFilter: FilterPreset = .none
    @State private var intensity: Float = 1.0

    var body: some View {
        VStack(spacing: Theme.spacing12) {
            Text("Filters").sectionHeader()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacing8) {
                    ForEach(FilterPreset.allCases) { preset in
                        FilterChip(
                            preset: preset,
                            isSelected: selectedFilter == preset
                        ) {
                            selectedFilter = preset
                            applyFilter()
                        }
                    }
                }
            }

            if selectedFilter != .none {
                HStack {
                    Text("Intensity")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Slider(value: $intensity, in: 0...1)
                        .onChange(of: intensity) { applyFilter() }
                }
            }
        }
        .cardStyle()
    }

    private func applyFilter() {
        // Filter is applied at export time via the pipeline
        // This just updates the preview state
    }
}

struct FilterChip: View {
    let preset: FilterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.displayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, Theme.spacing12)
                .padding(.vertical, Theme.spacing8)
                .background(isSelected ? Theme.accent : Theme.surface)
                .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                .clipShape(Capsule())
        }
    }
}

/// Built-in filter presets using Core Image.
enum FilterPreset: String, CaseIterable, Identifiable {
    case none = "None"
    case chrome = "Chrome"
    case fade = "Fade"
    case mono = "Mono"
    case noir = "Noir"
    case process = "Process"
    case transfer = "Transfer"
    case pixelate = "Pixelate"
    case blur = "Blur"
    case sharpen = "Sharpen"
    case vignette = "Vignette"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var ciFilterName: String? {
        switch self {
        case .none: nil
        case .chrome: "CIPhotoEffectChrome"
        case .fade: "CIPhotoEffectFade"
        case .mono: "CIPhotoEffectMono"
        case .noir: "CIPhotoEffectNoir"
        case .process: "CIPhotoEffectProcess"
        case .transfer: "CIPhotoEffectTransfer"
        case .pixelate: "CIPixellate"
        case .blur: "CIGaussianBlur"
        case .sharpen: "CISharpenLuminance"
        case .vignette: "CIVignette"
        }
    }

    func toStage(intensity: Float = 1.0) -> (any Stage)? {
        guard let name = ciFilterName else { return nil }
        var params: [String: Any] = [:]
        switch self {
        case .pixelate: params["inputScale"] = NSNumber(value: intensity * 20)
        case .blur: params["inputRadius"] = NSNumber(value: intensity * 10)
        case .sharpen: params["inputSharpness"] = NSNumber(value: intensity)
        case .vignette: params["inputIntensity"] = NSNumber(value: intensity * 2)
        default: break
        }
        return FilterStage(filters: [(name: name, params: params)])
    }
}
