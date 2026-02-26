import SwiftUI

struct LoginView: View {
    @Binding var isAuthenticated: Bool

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            VStack(spacing: AppTheme.paddingXLarge) {
                Spacer()

                // Logo
                Image(systemName: "cpu")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.primary)

                Text("AgentOS")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("AI Agent Platform")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer()

                // Skip login button (for now)
                Button {
                    Task {
                        try? await DatabaseService.shared.setSetting(key: "auth_token", value: "skip")
                        try? await DatabaseService.shared.setSetting(key: "user_id", value: "anonymous")
                        isAuthenticated = true
                    }
                } label: {
                    Text("Skip Login")
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.paddingStandard)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .padding(.horizontal, AppTheme.paddingXLarge)

                Spacer()
                    .frame(height: 40)
            }
        }
    }
}
