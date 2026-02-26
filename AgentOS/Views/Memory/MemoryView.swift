import SwiftUI

struct MemoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack {
                    Spacer()
                    Image(systemName: "lightbulb")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("Memory")
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Coming soon")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                }
            }
            .navigationTitle(String(localized: "Memory"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
