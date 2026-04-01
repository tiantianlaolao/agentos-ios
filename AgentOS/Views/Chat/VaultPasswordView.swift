import SwiftUI

struct VaultPasswordView: View {
    let isSetup: Bool
    let errorMessage: String?
    let onSubmit: (_ password: String, _ confirmPassword: String?, _ isSetup: Bool) -> Void
    let onDismiss: () -> Void

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError: String?
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("\u{1F512}")
                        .font(.system(size: 48))

                    Text(isSetup ? "设置秘洞密码" : "输入秘洞密码")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(isSetup ? "首次使用秘洞，请设置一个密码保护你的私密内容" : "输入密码解锁你的秘洞")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                // Password fields
                VStack(spacing: 16) {
                    SecureField("密码（至少4位）", text: $password)
                        .textContentType(.password)
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(AppTheme.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .focused($passwordFocused)

                    if isSetup {
                        SecureField("确认密码", text: $confirmPassword)
                            .textContentType(.password)
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AppTheme.surfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                }
                .padding(.horizontal, 32)

                // Error message
                if let error = localError ?? errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Submit button
                Button {
                    submitPassword()
                } label: {
                    Text(isSetup ? "设置密码" : "解锁")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                .fill(canSubmit ? AppTheme.primary : AppTheme.surfaceLighter)
                        )
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 32)

                Spacer()

                // Cancel button
                Button {
                    onDismiss()
                } label: {
                    Text("取消")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            passwordFocused = true
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        if isSetup {
            return password.count >= 4 && !confirmPassword.isEmpty
        } else {
            return password.count >= 4
        }
    }

    private func submitPassword() {
        localError = nil

        guard password.count >= 4 else {
            localError = "密码至少4位"
            return
        }

        if isSetup {
            guard password == confirmPassword else {
                localError = "两次密码不一致"
                return
            }
            onSubmit(password, confirmPassword, true)
        } else {
            onSubmit(password, nil, false)
        }
    }
}
