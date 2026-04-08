import SwiftUI

enum AppTheme {
    // MARK: - Colors (Warm white theme)

    static let background = Color(hex: "#FAF8F5")
    static let surface = Color(hex: "#FFFFFF")
    static let surfaceLight = Color(hex: "#F5F1EC")
    static let surfaceLighter = Color(hex: "#F5F1EC")

    static let primary = Color(hex: "#F4A56A")      // Warm orange
    static let primaryLight = Color(hex: "#F4B07A")
    static let primaryDark = Color(hex: "#E8845A")

    static let accent = Color(hex: "#22D3EE")        // Cyan
    static let textBrand = Color(hex: "#C4845A")     // Brand text color
    static let success = Color(hex: "#22C55E")       // Green
    static let warning = Color(hex: "#F59E0B")       // Amber
    static let error = Color(hex: "#EF4444")         // Red

    static let textPrimary = Color(hex: "#1E1810")
    static let textSecondary = Color(hex: "#2D2620")
    static let textTertiary = Color(hex: "#A09080")

    static let border = Color(hex: "#EDE8E2")
    static let divider = Color(hex: "#EDE8E2")

    static let userBubble = Color(hex: "#F4A56A")
    static let assistantBubble = Color(hex: "#FFFFFF")

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
