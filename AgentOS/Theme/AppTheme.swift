import SwiftUI

enum AppTheme {
    // MARK: - Colors (Dark theme, matching Android)

    static let background = Color(hex: "#0A0A0A")
    static let surface = Color(hex: "#1A1A1A")
    static let surfaceLight = Color(hex: "#2A2A2A")
    static let surfaceLighter = Color(hex: "#333333")

    static let primary = Color(hex: "#6366F1")      // Indigo
    static let primaryLight = Color(hex: "#818CF8")
    static let primaryDark = Color(hex: "#4F46E5")

    static let accent = Color(hex: "#22D3EE")        // Cyan
    static let success = Color(hex: "#22C55E")       // Green
    static let warning = Color(hex: "#F59E0B")       // Amber
    static let error = Color(hex: "#EF4444")         // Red

    static let textPrimary = Color(hex: "#F5F5F5")
    static let textSecondary = Color(hex: "#9CA3AF")
    static let textTertiary = Color(hex: "#6B7280")

    static let border = Color(hex: "#333333")
    static let divider = Color(hex: "#262626")

    static let userBubble = Color(hex: "#6366F1")
    static let assistantBubble = Color(hex: "#1E1E1E")

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 12
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16

    static let paddingSmall: CGFloat = 4
    static let paddingMedium: CGFloat = 6
    static let paddingStandard: CGFloat = 10
    static let paddingLarge: CGFloat = 14
    static let paddingXLarge: CGFloat = 20

    // MARK: - Typography

    static let titleFont = Font.system(size: 20, weight: .bold)
    static let headlineFont = Font.system(size: 17, weight: .semibold)
    static let bodyFont = Font.system(size: 15, weight: .regular)
    static let captionFont = Font.system(size: 13, weight: .regular)
    static let smallFont = Font.system(size: 11, weight: .regular)

    // MARK: - Chat-specific Typography (compact)

    static let chatBodyFont = Font.system(size: 15, weight: .regular)
    static let chatSmallFont = Font.system(size: 13, weight: .regular)
    static let chatTimeFont = Font.system(size: 10, weight: .regular)
    static let chatBubbleRadius: CGFloat = 16
    static let chatBubbleRadiusSmall: CGFloat = 4
    static let chatMessageSpacing: CGFloat = 3
}
