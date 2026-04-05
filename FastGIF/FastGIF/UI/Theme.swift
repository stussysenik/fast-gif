import SwiftUI

/// iA Writer-inspired design system — minimal, focused, typographic.
enum Theme {
    // MARK: - Colors
    static let background = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let accent = Color.blue
    static let destructive = Color.red
    static let success = Color.green
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)

    // MARK: - Spacing (4pt grid)
    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32

    // MARK: - Corner radius
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 20

    // MARK: - Animation
    static let springSnappy = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let springGentle = Animation.spring(response: 0.5, dampingFraction: 0.7)
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.spacing16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
}

struct SectionHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
    func sectionHeader() -> some View { modifier(SectionHeader()) }
}
