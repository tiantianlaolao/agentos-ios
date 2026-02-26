import SwiftUI

struct SettingsView: View {
    @Bindable var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: AppTheme.paddingXLarge) {
                    Spacer()

                    Image(systemName: "gearshape")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("Settings")
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Coming soon")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)

                    Spacer()

                    Button {
                        Task { await authViewModel.logout() }
                    } label: {
                        Text("Logout")
                            .font(AppTheme.headlineFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.paddingStandard)
                            .background(AppTheme.error)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                    .padding(.horizontal, AppTheme.paddingXLarge)
                    .padding(.bottom, AppTheme.paddingXLarge)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
