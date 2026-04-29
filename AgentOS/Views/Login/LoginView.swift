import SwiftUI

struct LoginView: View {
    @Bindable var authViewModel: AuthViewModel

    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var agreedToTerms = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 60)

                    // MARK: - Logo
                    VStack(spacing: 12) {
                        Group {
                            if let path = Bundle.main.path(forResource: "happy", ofType: "jpg", inDirectory: "Resources/Avatar"),
                               let uiImage = UIImage(contentsOfFile: path) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else if let path = Bundle.main.path(forResource: "happy", ofType: "jpg"),
                                      let uiImage = UIImage(contentsOfFile: path) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "cpu")
                                    .font(.system(size: 56))
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())

                        Text("AgentOS")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(.bottom, 36)

                    // MARK: - Tab Switcher
                    if !authViewModel.isResetMode {
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
                    } else {
                        Text(L10n.shared.locale == "zh" ? "重置密码" : "Reset Password")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.bottom, 28)
                    }

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

                        // Password (login/register only)
                        if !authViewModel.isResetMode {
                            fieldSection(label: L10n.tr("login.password")) {
                                secureField(
                                    text: $authViewModel.password,
                                    isVisible: showPassword,
                                    toggle: { showPassword.toggle() }
                                )
                            }

                            // Forgot password link (login only)
                            if authViewModel.isLogin {
                                HStack {
                                    Spacer()
                                    Button {
                                        authViewModel.isResetMode = true
                                        authViewModel.errorMessage = ""
                                        authViewModel.successMessage = ""
                                    } label: {
                                        Text(L10n.shared.locale == "zh" ? "忘记密码？" : "Forgot password?")
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppTheme.primary)
                                    }
                                }
                                .padding(.top, -10)
                            }
                        }

                        // Reset password fields
                        if authViewModel.isResetMode {
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
                                                        ? AppTheme.border
                                                        : AppTheme.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(authViewModel.countdown > 0)
                                }
                            }

                            // New Password
                            fieldSection(label: L10n.shared.locale == "zh" ? "新密码" : "New Password") {
                                secureField(
                                    text: $authViewModel.newPassword,
                                    isVisible: showPassword,
                                    toggle: { showPassword.toggle() }
                                )
                            }

                            // Confirm New Password
                            fieldSection(label: L10n.shared.locale == "zh" ? "确认新密码" : "Confirm New Password") {
                                secureField(
                                    text: $authViewModel.confirmNewPassword,
                                    isVisible: showConfirmPassword,
                                    toggle: { showConfirmPassword.toggle() }
                                )
                            }
                        }

                        // Register-only fields
                        if !authViewModel.isLogin && !authViewModel.isResetMode {
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
                                                        ? AppTheme.border
                                                        : AppTheme.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(authViewModel.countdown > 0)
                                }
                            }
                        }

                        // Agreement checkbox (register only)
                        if !authViewModel.isLogin && !authViewModel.isResetMode {
                            agreementCheckbox
                        }

                        // Error Message
                        if !authViewModel.errorMessage.isEmpty {
                            Text(authViewModel.errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        // Success Message
                        if !authViewModel.successMessage.isEmpty {
                            Text(authViewModel.successMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        // Submit Button
                        if authViewModel.isResetMode {
                            Button {
                                Task { await authViewModel.resetPassword() }
                            } label: {
                                Group {
                                    if authViewModel.isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(L10n.shared.locale == "zh" ? "重置密码" : "Reset Password")
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

                            Button {
                                authViewModel.isResetMode = false
                                authViewModel.errorMessage = ""
                                authViewModel.successMessage = ""
                            } label: {
                                Text(L10n.shared.locale == "zh" ? "返回登录" : "Back to Login")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .underline()
                            }
                            .padding(.top, 16)
                        } else {
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
                            .disabled(authViewModel.isLoading || (!authViewModel.isLogin && !agreedToTerms))
                            .opacity(authViewModel.isLoading || (!authViewModel.isLogin && !agreedToTerms) ? 0.6 : 1)
                            .padding(.top, 8)

                        }
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

    private var agreementCheckbox: some View {
        let isZh = L10n.shared.locale == "zh"
        let agreementURL = URL(string: isZh
            ? "https://www.tybbtech.com/zh/user-agreement"
            : "https://www.tybbtech.com/en/user-agreement")!
        let privacyURL = URL(string: isZh
            ? "https://www.tybbtech.com/zh/privacy-policy"
            : "https://www.tybbtech.com/en/privacy-policy")!

        return HStack(alignment: .top, spacing: 8) {
            Button {
                agreedToTerms.toggle()
            } label: {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(agreedToTerms ? AppTheme.primary : AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(L10n.tr("login.agreeTerms"))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(" ")
                    Link(L10n.tr("settings.userAgreement"), destination: agreementURL)
                        .foregroundStyle(AppTheme.textBrand)
                }
                HStack(spacing: 0) {
                    Text(L10n.tr("login.and"))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(" ")
                    Link(L10n.tr("settings.privacyPolicy"), destination: privacyURL)
                        .foregroundStyle(AppTheme.textBrand)
                }
            }
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
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
