import SwiftUI

/// Complaint / Report submission form (P1-C).
/// Login required — non-logged-in users see a "please login" prompt.
struct ComplaintFormView: View {
    @Bindable var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var description: String = ""
    @State private var email: String = ""
    @State private var submitting: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var didSucceed: Bool = false

    private static let maxDescription = 2000
    private static let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    private var canSubmit: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !submitting
    }

    var body: some View {
        Group {
            if authViewModel.isLoggedIn {
                formBody
            } else {
                loginPrompt
            }
        }
        .background(AppTheme.background)
        .navigationTitle(L10n.tr("complaint.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: $showAlert) {
            Button(L10n.tr("complaint.ok")) {
                if didSucceed { dismiss() }
            }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Form

    private var formBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("complaint.intro"))
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(L10n.tr("complaint.descriptionLabel"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("*")
                            .foregroundStyle(.red)
                    }
                    TextEditor(text: $description)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: description) { _, newValue in
                            if newValue.count > Self.maxDescription {
                                description = String(newValue.prefix(Self.maxDescription))
                            }
                        }
                    Text("\(description.count) / \(Self.maxDescription)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Email
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("complaint.emailLabel"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    TextField(L10n.tr("complaint.emailPlaceholder"), text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(L10n.tr("complaint.emailHelper"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }

                // Submit
                Button(action: handleSubmit) {
                    HStack {
                        if submitting {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Text(L10n.tr("complaint.submit"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? AppTheme.primary : AppTheme.primary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canSubmit)
                .padding(.top, 8)

                Text(L10n.tr("complaint.disclaimer"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(16)
        }
    }

    // MARK: - Login Prompt

    private var loginPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(L10n.tr("complaint.loginRequired"))
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                dismiss()
            } label: {
                Text(L10n.tr("complaint.goLogin"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }
    }

    // MARK: - Submit

    private func handleSubmit() {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty {
            showError(L10n.tr("complaint.errorDescriptionRequired"))
            return
        }
        if desc.count > Self.maxDescription {
            showError(L10n.tr("complaint.errorDescriptionTooLong"))
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty,
           trimmedEmail.range(of: Self.emailRegex, options: .regularExpression) == nil {
            showError(L10n.tr("complaint.errorInvalidEmail"))
            return
        }

        Task {
            await doSubmit(description: desc, email: trimmedEmail.isEmpty ? nil : trimmedEmail)
        }
    }

    private func doSubmit(description: String, email: String?) async {
        submitting = true
        defer { submitting = false }

        let token: String
        do {
            guard let t = try await DatabaseService.shared.getSetting(key: "auth_token"), !t.isEmpty else {
                showError(L10n.tr("complaint.errorLoginRequired"))
                return
            }
            token = t
        } catch {
            showError(L10n.tr("complaint.errorLoginRequired"))
            return
        }

        do {
            let response = try await SafetyAPIService.shared.submitComplaint(
                description: description,
                email: email,
                authToken: token
            )
            if response.ok {
                alertTitle = L10n.tr("complaint.successTitle")
                alertMessage = response.message ?? L10n.tr("complaint.successMessage")
                didSucceed = true
                showAlert = true
            } else {
                showError(response.error ?? L10n.tr("complaint.errorGeneric"))
            }
        } catch {
            showError(L10n.tr("complaint.errorNetwork"))
        }
    }

    private func showError(_ msg: String) {
        alertTitle = L10n.tr("complaint.errorTitle")
        alertMessage = msg
        didSucceed = false
        showAlert = true
    }
}
