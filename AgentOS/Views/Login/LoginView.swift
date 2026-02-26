import SwiftUI

struct LoginView: View {
    @Bindable var authViewModel: AuthViewModel

    @State private var showPassword = false
    @State private var showConfirmPassword = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // MARK: - Logo
                    VStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 56))
                            .foregroundStyle(AppTheme.primary)

                        Text("AgentOS")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(.bottom, 36)

                    // MARK: - Tab Switcher
                    HStack(spacing: 0) {
                        tabButton(title: L10n.tr("login.loginTab"), isSelected: authViewModel.isLogin) {
                            authViewModel.isLogin = true
                            authViewModel.errorMessage = ""
                        }
                        tabButton(title: L10n.tr("login.registerTab"), isSelected: !authViewModel.isLogin) {
                            authViewModel.isLogin = false
                            authViewModel.errorMessage = ""
                        }
                    }
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .padding(.horizontal, AppTheme.paddingXLarge)
                    .padding(.bottom, 28)

                    // MARK: - Form Fields
                    VStack(spacing: 18) {
                        // Phone
                        fieldSection(label: L10n.tr("login.phone")) {
                            TextField("13800138000", text: $authViewModel.phone)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        // Password
                        fieldSection(label: L10n.tr("login.password")) {
                            secureField(
                                text: $authViewModel.password,
                                isVisible: showPassword,
                                toggle: { showPassword.toggle() }
                            )
                        }

                        // Register-only fields
                        if !authViewModel.isLogin {
                            // Confirm Password
                            fieldSection(label: L10n.tr("login.confirmPassword")) {
                                secureField(
                                    text: $authViewModel.confirmPassword,
                                    isVisible: showConfirmPassword,
                                    toggle: { showConfirmPassword.toggle() }
                                )
                            }

                            // SMS Code
                            fieldSection(label: L10n.tr("login.code")) {
                                HStack(spacing: 10) {
                                    TextField("123456", text: $authViewModel.smsCode)
                                        .keyboardType(.numberPad)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 13)
                                        .background(AppTheme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Button {
                                        Task { await authViewModel.sendSmsCode() }
                                    } label: {
                                        Text(authViewModel.countdown > 0
                                             ? L10n.tr("login.resendIn", ["seconds": "\(authViewModel.countdown)"])
                                             : L10n.tr("login.sendCode"))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 13)
                                            .frame(minWidth: 100)
                                            .background(authViewModel.countdown > 0
                                                        ? Color(hex: "#3a3a5e")
                                                        : AppTheme.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(authViewModel.countdown > 0)
                                }
                            }
                        }

                        // Error Message
                        if !authViewModel.errorMessage.isEmpty {
                            Text(authViewModel.errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        // Submit Button
                        Button {
                            Task {
                                if authViewModel.isLogin {
                                    await authViewModel.login()
                                } else {
                                    await authViewModel.register()
                                }
                            }
                        } label: {
                            Group {
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(authViewModel.isLogin ? L10n.tr("login.submit") : L10n.tr("login.register"))
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .disabled(authViewModel.isLoading)
                        .opacity(authViewModel.isLoading ? 0.6 : 1)
                        .padding(.top, 8)

                        // Skip Login
                        Button {
                            authViewModel.skipLogin()
                        } label: {
                            Text(L10n.tr("login.skip"))
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textTertiary)
                                .underline()
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, AppTheme.paddingXLarge)

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Components

    private func tabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? .white : AppTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.primary : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(4)
    }

    private func fieldSection(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }

    private func secureField(
        text: Binding<String>,
        isVisible: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Group {
                if isVisible {
                    TextField("", text: text)
                } else {
                    SecureField("", text: text)
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.leading, 14)
            .padding(.vertical, 13)

            Button(action: toggle) {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.trailing, 14)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
