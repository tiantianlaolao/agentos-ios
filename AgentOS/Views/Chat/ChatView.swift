import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    var authViewModel: AuthViewModel

    @FocusState private var inputFocused: Bool
    @State private var showSkillsPanel = false
    @State private var skillsViewModel = SkillsViewModel()

    // Attachment state
    @State private var pendingAttachments: [Attachment] = []
    @State private var showAttachmentPicker = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showTodayScreen = false
    @State private var showBacktestWorkstation = false

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            if viewModel.showAgentHub {
                // Full-screen agent hub
                AgentHubView(
                    currentMode: viewModel.connectionMode,
                    isConnected: viewModel.isConnected,
                    onSelect: { mode in
                        skillsViewModel.clearSkills()
                        Task { await viewModel.switchMode(mode) }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.showAgentHub = false
                        }
                    },
                    onManageSkills: {
                        showSkillsPanel = true
                    }
                )
                .transition(.opacity)
            } else {
                // Chat interface
                VStack(spacing: 0) {
                    // Top bar
                    chatTopBar

                    // Connection banner
                    if !viewModel.isConnected && viewModel.connectionMode != .byok {
                        reconnectBanner
                    }

                    // Today screen or message list
                    if showTodayScreen {
                        TodayScreenView(
                            companionDays: authViewModel.companionDays,
                            onSuggestionTap: { message in
                                dismissTodayScreen()
                                viewModel.inputText = message
                                Task { await viewModel.sendMessage() }
                            },
                            onChatTap: {
                                dismissTodayScreen()
                                inputFocused = true
                            }
                        )
                        .transition(.opacity)
                    } else {
                        messageList
                    }

                    // Active skill card
                    if let skill = viewModel.activeSkill {
                        SkillCardView(skill: skill)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Attachment preview
                    if !pendingAttachments.isEmpty {
                        AttachmentPreviewView(attachments: pendingAttachments) { index in
                            pendingAttachments.remove(at: index)
                        }
                    }

                    // Upload indicator
                    if isUploading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(AppTheme.primary)
                                .controlSize(.small)
                            Text("Uploading...")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Input bar
                    inputBar
                }
            }
        }
        .task {
            await L10n.shared.loadLocale()
            await checkTodayScreen()
            await viewModel.connect()
        }
        .sheet(isPresented: $showSkillsPanel) {
            SkillsPanelView(
                viewModel: skillsViewModel,
                wsService: viewModel.wsService,
                mode: viewModel.connectionMode,
                onClose: { showSkillsPanel = false }
            )
        }
        .sheet(isPresented: $viewModel.showVaultPassword) {
            VaultPasswordView(
                isSetup: viewModel.isVaultSetup,
                errorMessage: viewModel.errorMessage,
                onSubmit: { password, confirmPassword, isSetup in
                    viewModel.sendVaultPassword(
                        password: password,
                        confirmPassword: confirmPassword,
                        isSetup: isSetup
                    )
                },
                onDismiss: {
                    viewModel.showVaultPassword = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showCompareSheet) {
            CompareModelSheet(
                onSelect: { modelId, modelName in
                    viewModel.compareWithModel(
                        originalContent: viewModel.compareOriginalContent,
                        model: modelId,
                        modelName: modelName
                    )
                },
                onDismiss: { viewModel.showCompareSheet = false }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showBacktestWorkstation) {
            BacktestWorkstationView()
        }
        .confirmationDialog("Add Attachment", isPresented: $showAttachmentPicker) {
            Button("Photo Library") { showPhotoPicker = true }
            Button("File") { showFilePicker = true }
            Button("Cancel", role: .cancel) { }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                isUploading = true
                defer { isUploading = false; selectedPhotoItem = nil }
                let deviceId = try? await DatabaseService.shared.getSetting(key: "deviceId")
                let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
                do {
                    let attachment = try await UploadService.shared.upload(
                        data: data,
                        fileName: "photo_\(Int(Date().timeIntervalSince1970)).jpg",
                        mimeType: "image/jpeg",
                        authToken: authToken,
                        deviceId: deviceId
                    )
                    await MainActor.run { pendingAttachments.append(attachment) }
                } catch {
                    print("Upload failed: \(error)")
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf, .plainText, .commaSeparatedText, .image, .html, .json, .xml, .zip, .spreadsheet, .presentation, .data]) { result in
            guard case .success(let url) = result else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            // Read data synchronously while security-scoped access is active
            guard let data = try? Data(contentsOf: url) else {
                url.stopAccessingSecurityScopedResource()
                return
            }
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            url.stopAccessingSecurityScopedResource()
            Task {
                isUploading = true
                defer { isUploading = false }
                let mimeType: String
                switch ext {
                case "pdf": mimeType = "application/pdf"
                case "jpg", "jpeg": mimeType = "image/jpeg"
                case "png": mimeType = "image/png"
                case "gif": mimeType = "image/gif"
                case "webp": mimeType = "image/webp"
                case "csv": mimeType = "text/csv"
                case "html", "htm": mimeType = "text/html"
                case "json": mimeType = "application/json"
                case "xml": mimeType = "application/xml"
                case "md", "markdown": mimeType = "text/markdown"
                case "zip": mimeType = "application/zip"
                case "doc": mimeType = "application/msword"
                case "docx": mimeType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                case "xlsx": mimeType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                case "pptx": mimeType = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
                default: mimeType = "application/octet-stream"
                }
                let deviceId = try? await DatabaseService.shared.getSetting(key: "deviceId")
                let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
                do {
                    let attachment = try await UploadService.shared.upload(
                        data: data,
                        fileName: fileName,
                        mimeType: mimeType,
                        authToken: authToken,
                        deviceId: deviceId
                    )
                    await MainActor.run { pendingAttachments.append(attachment) }
                } catch {
                    print("Upload failed: \(error)")
                }
            }
        }
    }

    // MARK: - Top Bar (replaces NavigationStack toolbar)

    private var chatTopBar: some View {
        HStack(spacing: 0) {
            // Left: Hub toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewModel.showAgentHub.toggle()
                }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Center: Title + companion days + connection status
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    if viewModel.isVaultMode {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                    }
                    Text(viewModel.isVaultMode ? L10n.tr("chat.vaultName") : L10n.tr("chat.appName"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(viewModel.isVaultMode ? AppTheme.warning : AppTheme.textPrimary)
                }
                if let days = authViewModel.companionDays {
                    Text(L10n.tr("chat.companionDays", ["days": "\(days)"]))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textBrand)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isConnected ? AppTheme.success : AppTheme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isConnected
                         ? modeName(viewModel.connectionMode)
                         : L10n.tr("chat.disconnected"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Spacer()

            // Right: Skills + More
            HStack(spacing: 4) {
                Button {
                    showSkillsPanel = true
                } label: {
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 44)
                }

                Menu {
                    if viewModel.isVaultMode {
                        Button {
                            viewModel.lockVault()
                        } label: {
                            Label("锁定秘洞", systemImage: "lock")
                        }
                    }
                    Button {
                        Task { await viewModel.clearConversation() }
                    } label: {
                        Label(L10n.tr("chat.clearChat"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 44)
                }
            }
        }
        .padding(.horizontal, 4)
        .background(AppTheme.background)
    }

    // MARK: - Reconnect Banner

    private var reconnectBanner: some View {
        Button {
            viewModel.reconnect()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11))
                Text(L10n.tr("chat.disconnected"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(AppTheme.warning)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(AppTheme.warning.opacity(0.1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Load more indicator
                    if viewModel.hasMore {
                        Button {
                            Task { await viewModel.loadMoreMessages() }
                        } label: {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(AppTheme.textTertiary)
                            } else {
                                Text(L10n.tr("chat.loadMore"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .padding(.top, 6)
                    }

                    // Messages with date separators
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        // Date separator
                        if shouldShowDateSeparator(at: index) {
                            DateSeparatorView(
                                label: Date.fromTimestamp(message.timestamp).chatDateLabel()
                            )
                        }

                        MessageBubbleView(
                            message: message,
                            onCopy: { viewModel.copyMessage(message) },
                            onDelete: { Task { await viewModel.deleteMessage(id: message.id) } },
                            onCompare: viewModel.connectionMode == .builtin ? { content in
                                viewModel.compareOriginalContent = content
                                viewModel.showCompareSheet = true
                            } : nil,
                            onBacktestAction: { _ in
                                showBacktestWorkstation = true
                            },
                            showAvatar: message.role == .assistant && isFirstInAssistantGroup(at: index)
                        )
                    }

                    // Streaming content
                    if let streaming = viewModel.streamingContent, !streaming.isEmpty {
                        StreamingBubbleView(
                            content: streaming,
                            showAvatar: viewModel.messages.last?.role != .assistant
                        )
                    } else if viewModel.isStreaming && viewModel.streamingContent == nil {
                        ThinkingBubbleView()
                    }

                    // Anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.streamingContent) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar (Telegram-style)

    private var inputBar: some View {
        HStack(spacing: 8) {
            // Attachment button
            Button(action: { showAttachmentPicker = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(AppTheme.primary)
            }
            .disabled(viewModel.isStreaming)

            // Text field
            TextField(L10n.tr("chat.inputPlaceholder"), text: $viewModel.inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit {
                    sendWithAttachments()
                }

            // Send / Stop button
            Button {
                if viewModel.isStreaming {
                    viewModel.stopGeneration()
                } else {
                    sendWithAttachments()
                }
            } label: {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        viewModel.isStreaming ? AppTheme.error :
                            (canSend ? AppTheme.primary : AppTheme.textTertiary)
                    )
            }
            .disabled(!viewModel.isStreaming && !canSend)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    private func sendWithAttachments() {
        let atts = pendingAttachments.isEmpty ? nil : pendingAttachments
        pendingAttachments = []
        Task { await viewModel.sendMessage(attachments: atts) }
    }

    private func isFirstInAssistantGroup(at index: Int) -> Bool {
        guard index >= 0 && index < viewModel.messages.count else { return false }
        if index == 0 { return true }
        return viewModel.messages[index - 1].role != .assistant
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = Date.fromTimestamp(viewModel.messages[index].timestamp)
        let previous = Date.fromTimestamp(viewModel.messages[index - 1].timestamp)
        return !Calendar.current.isDate(current, inSameDayAs: previous)
    }

    private func modeName(_ mode: ConnectionMode) -> String {
        switch mode {
        case .builtin: L10n.tr("chat.modeBuiltin")
        case .openclaw: "OpenClaw"
        case .copaw: "CoPaw"
        case .agent: L10n.tr("chat.tabAgent")
        case .byok: "BYOK"
        }
    }

    // MARK: - Today Screen

    private func checkTodayScreen() async {
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let lastGreeting = try? await DatabaseService.shared.getSetting(key: "lastGreetingDate")
        if lastGreeting != todayStr {
            showTodayScreen = true
        }
    }

    private func dismissTodayScreen() {
        withAnimation(.easeOut(duration: 0.3)) {
            showTodayScreen = false
        }
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        Task {
            try? await DatabaseService.shared.setSetting(key: "lastGreetingDate", value: todayStr)
        }
    }
}
