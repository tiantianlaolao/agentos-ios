import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SkillExecution

struct SkillExecution: Identifiable, Sendable {
    let id: String
    let name: String
    var description: String
    var isRunning: Bool
    var success: Bool?

    init(name: String, description: String, isRunning: Bool = true) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.isRunning = isRunning
    }
}

// MARK: - ChatViewModel

@MainActor
@Observable
final class ChatViewModel {
    // MARK: - Public State

    var messages: [ChatMessage] = []
    var currentConversationId: String?
    var streamingContent: String?
    var isStreaming = false
    var isConnected = false
    var connectionMode: ConnectionMode = .builtin
    var selectedProvider: LLMProvider = .deepseek
    var selectedModel: String = ""
    var inputText = ""
    var activeSkill: SkillExecution?
    var showAgentHub = true
    var errorMessage: String?

    // Pagination
    var hasMore = true
    var isLoadingMore = false

    // MARK: - Constants

    private let pageSize = 50
    private let cleanupThreshold = 500
    private let cleanupKeep = 200
    private let maxHistoryForLLM = 20

    // MARK: - Private State

    private var currentAssistantId: String?
    private var streamBuffer = ""
    private var currentUserId = "anonymous"

    // Services (wsService exposed for skills panel integration)
    let wsService = WebSocketService()
    private let openClawService = OpenClawDirectService()
    private let directLLMService = DirectLLMService.shared

    // BYOK streaming task
    private var byokStreamTask: Task<Void, Never>?

    // Throttling for streaming updates
    private var lastStreamUpdate: Date = .distantPast
    private let streamThrottleInterval: TimeInterval = 0.032 // ~30fps

    // Stream timeout
    private var streamTimeoutTask: Task<Void, Never>?
    private let streamTimeoutDuration: TimeInterval = 120

    // MARK: - Init

    init() {
        setupWebSocketHandlers()
        setupOpenClawHandlers()
    }

    // MARK: - User / Mode Management

    func loadSettings() async {
        do {
            // Load user ID
            if let userId = try await DatabaseService.shared.getSetting(key: "auth_userId"),
               !userId.isEmpty {
                currentUserId = userId
            } else {
                currentUserId = "anonymous"
            }

            // Load mode
            if let modeStr = try await DatabaseService.shared.getSetting(key: "mode"),
               let mode = ConnectionMode(rawValue: modeStr) {
                connectionMode = mode
            }

            // Load provider
            if let providerStr = try await DatabaseService.shared.getSetting(key: "provider"),
               let provider = LLMProvider(rawValue: providerStr) {
                selectedProvider = provider
            }

            // Load model
            if let model = try await DatabaseService.shared.getSetting(key: "selectedModel") {
                selectedModel = model
            }
        } catch {
            print("[ChatVM] Failed to load settings: \(error)")
        }
    }

    // MARK: - Conversation Management

    /// Get effective conversation mode: builtin & byok share "builtin", others are separate
    private func conversationMode(_ mode: ConnectionMode) -> ConnectionMode {
        switch mode {
        case .openclaw: return .openclaw
        case .copaw: return .copaw
        case .builtin, .byok: return .builtin
        }
    }

    func loadOrCreateConversation() async {
        do {
            let conv = try await DatabaseService.shared.getOrCreateSingleConversation(
                mode: conversationMode(connectionMode),
                userId: currentUserId
            )
            currentConversationId = conv.id
            await loadMessages(conversationId: conv.id)
        } catch {
            print("[ChatVM] Failed to load conversation: \(error)")
        }
    }

    private func loadMessages(conversationId: String) async {
        do {
            let msgs = try await DatabaseService.shared.getMessagesPaginated(
                conversationId: conversationId,
                limit: pageSize
            )
            messages = msgs
            let total = try await DatabaseService.shared.getMessageCount(conversationId: conversationId)
            hasMore = msgs.count < total
        } catch {
            print("[ChatVM] Failed to load messages: \(error)")
        }
    }

    func loadMoreMessages() async {
        guard let convId = currentConversationId,
              !isLoadingMore,
              hasMore,
              let oldest = messages.first else { return }

        isLoadingMore = true
        do {
            let older = try await DatabaseService.shared.getMessagesPaginated(
                conversationId: convId,
                limit: pageSize,
                beforeTimestamp: oldest.timestamp
            )
            if older.isEmpty {
                hasMore = false
            } else {
                messages.insert(contentsOf: older, at: 0)
                if older.count < pageSize { hasMore = false }
            }
        } catch {
            print("[ChatVM] Failed to load more: \(error)")
        }
        isLoadingMore = false
    }

    // MARK: - Connection

    func connect() async {
        await loadSettings()
        await loadOrCreateConversation()

        // Decide connection strategy based on mode
        switch connectionMode {
        case .openclaw:
            await connectOpenClaw()
        case .builtin, .copaw:
            connectWebSocket()
        case .byok:
            // BYOK doesn't need a persistent connection — calls API directly
            isConnected = true
        }
    }

    func disconnect() {
        wsService.disconnect()
        openClawService.disconnect()
        byokStreamTask?.cancel()
        byokStreamTask = nil
        cancelStreamTimeout()
        isConnected = false
    }

    func switchMode(_ mode: ConnectionMode) async {
        guard mode != connectionMode else { return }
        disconnect()
        resetStreamingState()
        connectionMode = mode
        Task {
            try? await DatabaseService.shared.setSetting(key: "mode", value: mode.rawValue)
        }
        await connect()
    }

    private func connectWebSocket() {
        var options = WebSocketService.ConnectOptions()

        Task {
            let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
            let apiKey = try? await DatabaseService.shared.getSetting(key: "apiKey")
            let deviceId = await getOrCreateDeviceId()

            options.authToken = authToken
            options.deviceId = deviceId

            if connectionMode == .copaw {
                let copawUrl = try? await DatabaseService.shared.getSetting(key: "copawUrl")
                let copawToken = try? await DatabaseService.shared.getSetting(key: "copawToken")
                let copawSubMode = try? await DatabaseService.shared.getSetting(key: "copawSubMode")
                options.copawUrl = copawUrl
                options.copawToken = copawToken
                options.copawHosted = copawSubMode == "hosted"
            }

            if connectionMode == .builtin {
                let builtinSubMode = try? await DatabaseService.shared.getSetting(key: "builtinSubMode")
                if builtinSubMode == "byok" {
                    options.provider = selectedProvider
                    options.apiKey = apiKey
                    options.model = selectedModel.isEmpty ? nil : selectedModel
                }
            }

            wsService.connect(mode: connectionMode, options: options)
        }
    }

    private func connectOpenClaw() async {
        do {
            let openclawUrl = try await DatabaseService.shared.getSetting(key: "openclawUrl") ?? ""
            let openclawToken = try await DatabaseService.shared.getSetting(key: "openclawToken") ?? ""

            guard !openclawUrl.isEmpty else {
                errorMessage = "OpenClaw URL not configured"
                return
            }

            openClawService.configure(url: openclawUrl, token: openclawToken)
            try await openClawService.ensureConnected()
            isConnected = true
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func reconnect() {
        switch connectionMode {
        case .openclaw:
            openClawService.reconnectNow()
        case .byok:
            isConnected = true
        default:
            wsService.reconnectNow()
        }
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        guard var convId = currentConversationId else { return }

        // Ensure conversation exists
        if convId.isEmpty {
            do {
                let conv = try await DatabaseService.shared.getOrCreateSingleConversation(
                    mode: conversationMode(connectionMode),
                    userId: currentUserId
                )
                convId = conv.id
                currentConversationId = convId
            } catch { return }
        }

        // Update conversation title
        do {
            let conv = try await DatabaseService.shared.getOrCreateSingleConversation(
                mode: conversationMode(connectionMode),
                userId: currentUserId
            )
            var updated = conv
            if conv.title == "Chat" {
                updated.title = String(text.prefix(30))
            }
            updated.updatedAt = Int(Date().timeIntervalSince1970 * 1000)
            try await DatabaseService.shared.saveConversation(updated)
        } catch { /* ignore */ }

        // Add user message
        let userMsg = ChatMessage(
            conversationId: convId,
            role: .user,
            content: text
        )
        messages.append(userMsg)
        inputText = ""
        try? await DatabaseService.shared.saveMessage(userMsg)

        // Init streaming state
        let assistantId = UUID().uuidString
        currentAssistantId = assistantId
        streamBuffer = ""
        isStreaming = true
        streamingContent = nil

        // Build history
        let history = buildHistory()

        // Route by mode
        switch connectionMode {
        case .builtin, .copaw:
            startStreamTimeout()
            wsService.sendChat(
                conversationId: convId,
                content: text,
                history: history
            )

        case .byok:
            await sendBYOK(text: text, convId: convId, history: history)

        case .openclaw:
            await sendOpenClaw(text: text, convId: convId)
        }
    }

    // MARK: - Stop Generation

    func stopGeneration() {
        cancelStreamTimeout()

        if let convId = currentConversationId {
            switch connectionMode {
            case .builtin, .copaw:
                wsService.sendChatStop(conversationId: convId)
            case .openclaw:
                Task { await openClawService.abortChat() }
            case .byok:
                byokStreamTask?.cancel()
                byokStreamTask = nil
            }
        }

        // Finalize current stream as message
        if let assistantId = currentAssistantId, !streamBuffer.isEmpty {
            let convId = currentConversationId ?? ""
            let msg = ChatMessage(
                id: assistantId,
                conversationId: convId,
                role: .assistant,
                content: streamBuffer
            )
            messages.append(msg)
            Task { try? await DatabaseService.shared.saveMessage(msg) }
        }

        resetStreamingState()
    }

    // MARK: - Clear Conversation

    func clearConversation() async {
        guard let convId = currentConversationId else { return }
        do {
            try await DatabaseService.shared.clearConversationMessages(conversationId: convId)
        } catch { /* ignore */ }
        messages = []
        hasMore = false
        resetStreamingState()
    }

    // MARK: - Delete Message

    func deleteMessage(id: String) async {
        do {
            try await DatabaseService.shared.deleteMessage(id: id)
        } catch { /* ignore */ }
        messages.removeAll { $0.id == id }
    }

    // MARK: - Copy Message

    func copyMessage(_ message: ChatMessage) {
        #if canImport(UIKit)
        UIPasteboard.general.string = message.content
        #endif
    }

    // MARK: - BYOK Direct Streaming

    private func sendBYOK(text: String, convId: String, history: [ChatHistoryItem]) async {
        let apiKey: String
        do {
            apiKey = try await DatabaseService.shared.getSetting(key: "apiKey") ?? ""
        } catch {
            apiKey = ""
        }

        guard !apiKey.isEmpty else {
            addErrorMessage("API key not configured", conversationId: convId)
            resetStreamingState()
            return
        }

        let chatMessages = history.map { (role: $0.role, content: $0.content) }
            + [(role: "user", content: text)]

        let model = selectedModel.isEmpty ? nil : selectedModel

        byokStreamTask = Task { [weak self] in
            guard let self else { return }
            await self.directLLMService.streamChat(
                provider: self.selectedProvider,
                apiKey: apiKey,
                model: model,
                messages: chatMessages,
                onChunk: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        self?.handleStreamChunk(delta: delta)
                    }
                },
                onDone: { [weak self] fullContent in
                    Task { @MainActor [weak self] in
                        self?.handleStreamDone(fullContent: fullContent, conversationId: convId)
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleStreamError(error: error, conversationId: convId)
                    }
                }
            )
        }
    }

    // MARK: - OpenClaw Direct Streaming

    private func sendOpenClaw(text: String, convId: String) async {
        openClawService.onChunk = { [weak self] delta in
            Task { @MainActor [weak self] in
                self?.handleStreamChunk(delta: delta)
            }
        }
        openClawService.onDone = { [weak self] fullContent in
            Task { @MainActor [weak self] in
                self?.handleStreamDone(fullContent: fullContent, conversationId: convId)
            }
        }
        openClawService.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleStreamError(error: error, conversationId: convId)
            }
        }
        openClawService.onToolEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.phase == "start" {
                    self.activeSkill = SkillExecution(
                        name: event.name,
                        description: "Running \(event.name)..."
                    )
                } else {
                    self.activeSkill?.isRunning = false
                    self.activeSkill?.success = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        self.activeSkill = nil
                    }
                }
            }
        }

        await openClawService.sendChat(content: text)
    }

    // MARK: - WebSocket Handlers

    private func setupWebSocketHandlers() {
        wsService.onMessage { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleWSMessage(message)
            }
        }
    }

    private func handleWSMessage(_ message: WSMessage) {
        switch message.type {
        case .connected:
            isConnected = true

        case .chatChunk:
            if let payload = message.payload?.dictValue,
               let delta = payload["delta"] as? String {
                handleStreamChunk(delta: delta)
                resetStreamTimeout()
            }

        case .chatDone:
            cancelStreamTimeout()
            if let payload = message.payload?.dictValue,
               let fullContent = payload["fullContent"] as? String,
               let convId = payload["conversationId"] as? String {
                handleStreamDone(fullContent: fullContent, conversationId: convId)
            }

        case .skillStart:
            if let payload = message.payload?.dictValue,
               let skillName = payload["skillName"] as? String,
               let desc = payload["description"] as? String {
                activeSkill = SkillExecution(name: skillName, description: desc)
            }

        case .skillResult:
            if let payload = message.payload?.dictValue,
               let skillName = payload["skillName"] as? String,
               let success = payload["success"] as? Bool {
                activeSkill?.isRunning = false
                activeSkill?.success = success
                activeSkill?.description = success ? "Done" : "Failed"
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    self.activeSkill = nil
                }
            }

        case .pushMessage:
            if let payload = message.payload?.dictValue,
               let content = payload["content"] as? String {
                handlePushMessage(content: content)
            }

        case .error:
            if let payload = message.payload?.dictValue {
                let code = payload["code"] as? String ?? ""
                let msg = payload["message"] as? String ?? "Unknown error"

                if code == "CONNECTION_CLOSED" {
                    isConnected = false
                    return
                }

                cancelStreamTimeout()
                if currentAssistantId != nil {
                    resetStreamingState()
                }
                addErrorMessage(msg, conversationId: payload["conversationId"] as? String)
            }

        default:
            break
        }
    }

    // MARK: - OpenClaw Connection Handlers

    private func setupOpenClawHandlers() {
        openClawService.onConnectionChange = { [weak self] connected in
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        openClawService.onPush = { [weak self] content in
            Task { @MainActor [weak self] in
                self?.handlePushMessage(content: content)
            }
        }
    }

    // MARK: - Stream Handling (shared)

    private func handleStreamChunk(delta: String) {
        guard currentAssistantId != nil else { return }
        streamBuffer += delta

        let now = Date()
        if now.timeIntervalSince(lastStreamUpdate) > streamThrottleInterval {
            streamingContent = streamBuffer
            lastStreamUpdate = now
        }
    }

    private func handleStreamDone(fullContent: String, conversationId: String) {
        guard let assistantId = currentAssistantId else { return }

        let msg = ChatMessage(
            id: assistantId,
            conversationId: conversationId,
            role: .assistant,
            content: fullContent
        )
        messages.append(msg)
        Task {
            try? await DatabaseService.shared.saveMessage(msg)
            await checkAndCleanup(conversationId: conversationId)
        }

        resetStreamingState()
    }

    private func handleStreamError(error: String, conversationId: String) {
        resetStreamingState()
        addErrorMessage(error, conversationId: conversationId)
    }

    private func handlePushMessage(content: String) {
        guard let convId = currentConversationId, !content.isEmpty else { return }
        let msg = ChatMessage(
            conversationId: convId,
            role: .assistant,
            content: content,
            skillName: "push"
        )
        messages.append(msg)
        Task { try? await DatabaseService.shared.saveMessage(msg) }
    }

    // MARK: - Helpers

    private func resetStreamingState() {
        isStreaming = false
        streamingContent = nil
        streamBuffer = ""
        currentAssistantId = nil
        activeSkill = nil
        byokStreamTask?.cancel()
        byokStreamTask = nil
    }

    private func addErrorMessage(_ text: String, conversationId: String? = nil) {
        let convId = conversationId ?? currentConversationId ?? ""
        let msg = ChatMessage(
            conversationId: convId,
            role: .assistant,
            content: "[Error] \(text)"
        )
        messages.append(msg)
        errorMessage = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.errorMessage == text {
                self.errorMessage = nil
            }
        }
    }

    private func buildHistory() -> [ChatHistoryItem] {
        let recent = messages.suffix(maxHistoryForLLM * 2)
        return recent.map { ChatHistoryItem(role: $0.role.rawValue, content: $0.content) }
    }

    private func getOrCreateDeviceId() async -> String {
        do {
            if let existing = try await DatabaseService.shared.getSetting(key: "deviceId"),
               !existing.isEmpty {
                return existing
            }
            let newId = UUID().uuidString
            try await DatabaseService.shared.setSetting(key: "deviceId", value: newId)
            return newId
        } catch {
            return UUID().uuidString
        }
    }

    // MARK: - Stream Timeout

    private func startStreamTimeout() {
        cancelStreamTimeout()
        streamTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.streamTimeoutDuration ?? 120))
            guard !Task.isCancelled, let self else { return }

            // Timeout: save whatever we have
            if let assistantId = self.currentAssistantId, !self.streamBuffer.isEmpty {
                let convId = self.currentConversationId ?? ""
                let msg = ChatMessage(
                    id: assistantId,
                    conversationId: convId,
                    role: .assistant,
                    content: self.streamBuffer
                )
                self.messages.append(msg)
                Task { try? await DatabaseService.shared.saveMessage(msg) }
            }

            self.addErrorMessage("Stream timed out", conversationId: self.currentConversationId)
            self.resetStreamingState()
        }
    }

    private func resetStreamTimeout() {
        startStreamTimeout()
    }

    private func cancelStreamTimeout() {
        streamTimeoutTask?.cancel()
        streamTimeoutTask = nil
    }

    // MARK: - Auto Cleanup

    private func checkAndCleanup(conversationId: String) async {
        do {
            let total = try await DatabaseService.shared.getMessageCount(conversationId: conversationId)
            guard total > cleanupThreshold else { return }
            let toDelete = total - cleanupKeep
            _ = try await DatabaseService.shared.deleteOldestMessages(
                conversationId: conversationId,
                count: toDelete
            )
            // Reload messages
            await loadMessages(conversationId: conversationId)
        } catch {
            print("[ChatVM] Cleanup failed: \(error)")
        }
    }
}
