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

                VStack(spacing: 0) {
                    // Agent hub (collapsible)
                    if viewModel.showAgentHub {
                        AgentHubView(
                            currentMode: viewModel.connectionMode,
                            isConnected: viewModel.isConnected,
                            onSelect: { mode in
                                Task { await viewModel.switchMode(mode) }
                                viewModel.showAgentHub = false
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

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
            .navigationTitle("AgentOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showAgentHub.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.showAgentHub ? "chevron.up" : "square.grid.2x2")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showSkillsPanel = true
                        } label: {
                            Image(systemName: "puzzlepiece")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Menu {
                            Button {
                                Task { await viewModel.clearConversation() }
                            } label: {
                                Label(String(localized: "Clear Chat"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .task {
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
                    .font(.system(size: 12))
                Text("Disconnected. Tap to reconnect.")
                    .font(AppTheme.smallFont)
            }
            .foregroundStyle(AppTheme.warning)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(AppTheme.warning.opacity(0.1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.paddingMedium) {
                    // Load more indicator
                    if viewModel.hasMore {
                        Button {
                            Task { await viewModel.loadMoreMessages() }
                        } label: {
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(AppTheme.textTertiary)
                            } else {
                                Text("Load earlier messages")
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
            TextField(String(localized: "Message..."), text: $viewModel.inputText, axis: .vertical)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
                    .font(.system(size: 32))
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
