import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    @FocusState private var inputFocused: Bool
    @State private var showSkillsPanel = false
    @State private var skillsViewModel = SkillsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if viewModel.showAgentHub {
                    // Full-screen agent hub
                    AgentHubView(
                        currentMode: viewModel.connectionMode,
                        isConnected: viewModel.isConnected,
                        onSelect: { mode in
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
                        // Connection banner
                        if !viewModel.isConnected && viewModel.connectionMode != .byok {
                            reconnectBanner
                        }

                        // Message list
                        messageList

                        // Active skill card
                        if let skill = viewModel.activeSkill {
                            SkillCardView(skill: skill)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Input bar
                        inputBar
                    }
                }
            }
            .navigationTitle("AgentOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.showAgentHub.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.showAgentHub ? "xmark" : "square.grid.2x2")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                if !viewModel.showAgentHub {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button {
                                showSkillsPanel = true
                            } label: {
                                Image(systemName: "puzzlepiece")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Menu {
                                Button {
                                    Task { await viewModel.clearConversation() }
                                } label: {
                                    Label(L10n.tr("chat.clearChat"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .task {
                await L10n.shared.loadLocale()
                await viewModel.connect()
            }
            .sheet(isPresented: $showSkillsPanel) {
                SkillsPanelView(
                    viewModel: skillsViewModel,
                    wsService: viewModel.wsService,
                    onClose: { showSkillsPanel = false }
                )
            }
        }
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
                    .font(AppTheme.smallFont)
            }
            .foregroundStyle(AppTheme.warning)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(AppTheme.warning.opacity(0.1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.chatMessageSpacing) {
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
                                    .font(AppTheme.smallFont)
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .padding(.top, AppTheme.paddingMedium)
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
                            onDelete: { Task { await viewModel.deleteMessage(id: message.id) } }
                        )
                    }

                    // Streaming content
                    if let streaming = viewModel.streamingContent, !streaming.isEmpty {
                        StreamingBubbleView(content: streaming)
                    } else if viewModel.isStreaming && viewModel.streamingContent == nil {
                        ThinkingBubbleView()
                    }

                    // Anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.vertical, AppTheme.paddingMedium)
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

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: AppTheme.paddingMedium) {
            TextField(L10n.tr("chat.inputPlaceholder"), text: $viewModel.inputText, axis: .vertical)
                .font(AppTheme.chatBodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            // Send / Stop button
            Button {
                if viewModel.isStreaming {
                    viewModel.stopGeneration()
                } else {
                    Task { await viewModel.sendMessage() }
                }
            } label: {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        viewModel.isStreaming ? AppTheme.error :
                            (viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? AppTheme.textTertiary : AppTheme.primary)
                    )
            }
            .disabled(!viewModel.isStreaming && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, AppTheme.paddingLarge)
        .padding(.vertical, AppTheme.paddingMedium)
        .background(AppTheme.surface)
    }

    // MARK: - Helpers

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = Date.fromTimestamp(viewModel.messages[index].timestamp)
        let previous = Date.fromTimestamp(viewModel.messages[index - 1].timestamp)
        return !Calendar.current.isDate(current, inSameDayAs: previous)
    }
}
