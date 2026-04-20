import SwiftUI

struct QuotaExceededModalView: View {
    let message: String
    let onUpgrade: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 12) {
                Text("⏳").font(.system(size: 40))
                Text("额度已用完")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                VStack(spacing: 8) {
                    Button(action: onUpgrade) {
                        Text("升级会员")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button(action: onClose) {
                        Text("稍后再说")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(24)
        }
    }
}
