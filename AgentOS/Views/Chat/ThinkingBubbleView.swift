import SwiftUI

struct ThinkingBubbleView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Avatar - thinking state
            AssistantAvatarView(size: .small, state: .thinking, animated: true)

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
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(AppTheme.border, lineWidth: 1)
            )

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
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
