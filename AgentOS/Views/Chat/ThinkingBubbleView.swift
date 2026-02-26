import SwiftUI

struct ThinkingBubbleView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.paddingMedium) {
            // Avatar
            Circle()
                .fill(AppTheme.surfaceLight)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primary)
                }

            // Bubble with dots
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppTheme.textTertiary)
                        .frame(width: 8, height: 8)
                        .offset(y: dotOffset(for: index))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppTheme.paddingLarge)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = max(0, min(1, phase - CGFloat(delay)))
        return -6 * sin(progress * .pi)
    }
}
