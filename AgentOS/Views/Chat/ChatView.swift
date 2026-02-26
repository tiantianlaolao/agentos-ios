import SwiftUI

struct ChatView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack {
                    Spacer()
                    Text("Chat")
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Coming soon")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                }
            }
            .navigationTitle("AgentOS")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
