import SwiftUI

struct MemoryView: View {
    @State private var viewModel = MemoryViewModel()
    @State private var isLoggedIn = false
    @State private var isBuiltinMode = true

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if !isLoggedIn {
                notLoggedInView
            } else if !isBuiltinMode {
                externalModeView
            } else if viewModel.isLoading {
                ProgressView()
                    .tint(AppTheme.primary)
            } else if viewModel.isEditing {
                editingView
            } else {
                readView
            }
        }
        .navigationTitle(L10n.tr("memory.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isLoggedIn && isBuiltinMode && !viewModel.isLoading {
                if viewModel.isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("memory.cancel")) {
                            viewModel.cancelEditing()
                        }
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(viewModel.isSaving ? L10n.tr("memory.saving") : L10n.tr("memory.save")) {
                            Task { await viewModel.saveMemory() }
                        }
                        .foregroundStyle(AppTheme.primary)
                        .disabled(!viewModel.hasChanges || viewModel.isSaving)
                    }
                }
            }
        }
        .task {
            await checkAuthState()
            if isLoggedIn && isBuiltinMode {
                await viewModel.loadMemory()
            }
        }
    }

    // MARK: - Subviews

    private var notLoggedInView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textTertiary)
            Text(L10n.tr("memory.loginRequired"))
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var externalModeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cloud")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.textTertiary)
            Text(L10n.tr("memory.externalAgent"))
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var readView: some View {
        VStack(spacing: 0) {
            if viewModel.memoryText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "lightbulb")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(L10n.tr("memory.noContent"))
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(.horizontal, 40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(viewModel.memoryText)
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .textSelection(.enabled)

                        if let formatted = viewModel.formattedUpdatedAt {
                            Text(L10n.tr("memory.updated", ["time": formatted]))
                                .font(AppTheme.smallFont)
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        Text(L10n.tr("memory.characters", ["count": "\(viewModel.charCount)"]))
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(20)
                }
            }

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.error)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            // Bottom edit button
            VStack {
                Divider()
                    .background(AppTheme.divider)
                Button {
                    viewModel.startEditing()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text(L10n.tr("memory.edit"))
                    }
                    .font(AppTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var editingView: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.editText)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            HStack {
                Spacer()
                Text(L10n.tr("memory.characters", ["count": "\(viewModel.charCount)"]))
                    .font(AppTheme.smallFont)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Helpers

    private func checkAuthState() async {
        let token = try? await DatabaseService.shared.getSetting(key: "auth_token")
        let skipped = try? await DatabaseService.shared.getSetting(key: "auth_skipped")
        let loggedIn = try? await DatabaseService.shared.getSetting(key: "auth_loggedIn")
        let userId = try? await DatabaseService.shared.getSetting(key: "auth_userId")
        isLoggedIn = (loggedIn == "true" && token != nil && !(token ?? "").isEmpty)

        // Read mode with user-specific key
        let userKey = (userId != nil && !userId!.isEmpty) ? "\(userId!):mode" : "mode"
        let mode = try? await DatabaseService.shared.getSetting(key: userKey)
        isBuiltinMode = (mode == nil || mode == "builtin")

        // If user skipped login, they're authenticated but not "logged in" for memory
        if skipped == "true" && (token == nil || (token ?? "").isEmpty) {
            isLoggedIn = false
        }
    }
}
