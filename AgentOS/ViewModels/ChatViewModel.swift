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
    var showAgentHub = false
    var errorMessage: String?
    var showCompareSheet = false
    var compareOriginalContent = ""

    // Vault (Midong 秘洞) state
    var isVaultMode = false
    var showVaultPassword = false
    var isVaultSetup = false
    private var vaultClosePending = false // marks the AI's close response as vault too

    // Pagination
    var hasMore = true
    var isLoadingMore = false

    // MARK: - Constants

    /// Build user-specific settings key
    private func ukey(_ key: String) -> String {
        currentUserId != "anonymous" ? "\(currentUserId):\(key)" : key
    }

    private let pageSize = 50
    private let cleanupThreshold = 500
    private let cleanupKeep = 200
    private let maxHistoryForLLM = 20

    // MARK: - Private State

    private var currentAssistantId: String?
    private var graceRecoveryConversationId: String?
    private var graceRecoveryPartialAssistantId: String?
    private var streamBuffer = ""
    private var currentUserId = "anonymous"
    /// True when OpenClaw mode uses WebSocket server proxy (empty URL, admin user)
    private var openclawProxyMode = false
    private var welcomeShown = false

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
    private let streamTimeoutDuration: TimeInterval = 300

    // MARK: - Init

    init() {
        setupWebSocketHandlers()
        setupOpenClawHandlers()
    }

    // MARK: - User / Mode Management

    func loadSettings() async {
        do {
            // Load user ID (auth keys are global)
            if let userId = try await DatabaseService.shared.getSetting(key: "auth_userId"),
               !userId.isEmpty {
                currentUserId = userId
            } else {
                currentUserId = "anonymous"
            }

            // User-specific key helper
            func ukey(_ key: String) -> String {
                currentUserId != "anonymous" ? "\(currentUserId):\(key)" : key
            }

            // Load user-specific settings
            if let modeStr = try await DatabaseService.shared.getSetting(key: ukey("mode")),
               let mode = ConnectionMode(rawValue: modeStr) {
                connectionMode = mode
            }

            if let providerStr = try await DatabaseService.shared.getSetting(key: ukey("provider")),
               let provider = LLMProvider(rawValue: providerStr) {
                selectedProvider = provider
            }

            if let model = try await DatabaseService.shared.getSetting(key: ukey("selectedModel")) {
                selectedModel = model
            }
        } catch {
            print("[ChatVM] Failed to load settings: \(error)")
        }
    }

    // MARK: - Conversation Management

    /// Get effective conversation mode: builtin & byok share "builtin", others are separate.
    /// Note: Known agents (openclaw/copaw) will have connectionMode set to .openclaw/.copaw
    /// by connectAgent(), so .agent here is only reached by truly custom agents.
    private func conversationMode(_ mode: ConnectionMode) -> ConnectionMode {
        switch mode {
        case .openclaw: return .openclaw
        case .copaw: return .copaw
        case .agent: return .agent  // custom agents only
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
            // When not in vault mode, filter out vault messages
            let msgs: [ChatMessage]
            let total: Int
            if isVaultMode {
                msgs = try await DatabaseService.shared.getMessagesPaginated(
                    conversationId: conversationId,
                    limit: pageSize
                )
                total = try await DatabaseService.shared.getMessageCount(conversationId: conversationId)
            } else {
                msgs = try await DatabaseService.shared.getMessagesPaginatedNonVault(
                    conversationId: conversationId,
                    limit: pageSize
                )
                total = try await DatabaseService.shared.getNonVaultMessageCount(conversationId: conversationId)
            }
            messages = msgs
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
            let older: [ChatMessage]
            if isVaultMode {
                older = try await DatabaseService.shared.getMessagesPaginated(
                    conversationId: convId,
                    limit: pageSize,
                    beforeTimestamp: oldest.timestamp
                )
            } else {
                older = try await DatabaseService.shared.getMessagesPaginatedNonVault(
                    conversationId: convId,
                    limit: pageSize,
                    beforeTimestamp: oldest.timestamp
                )
            }
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

        // Check if this mode came from agent settings (agentId matches)
        let agentId = try? await DatabaseService.shared.getSetting(key: ukey("agentId"))
        let isAgentOrigin: Bool
        switch connectionMode {
        case .openclaw: isAgentOrigin = (agentId == "openclaw")
        case .copaw: isAgentOrigin = (agentId == "copaw")
        case .agent: isAgentOrigin = true
        default: isAgentOrigin = false
        }

        // Decide connection strategy based on mode
        if isAgentOrigin {
            // Route through connectAgent() which uses agentUrl/agentToken/agentSubMode
            await connectAgent()
        } else {
            switch connectionMode {
            case .openclaw:
                await connectOpenClaw()
            case .builtin, .copaw:
                connectWebSocket()
            case .byok:
                // BYOK doesn't need a persistent connection — calls API directly
                isConnected = true
                showWelcomeIfNeeded()
            case .agent:
                // Fallback (should not reach here since isAgentOrigin handles it)
                await connectAgent()
            }
        }
    }

    private func showWelcomeIfNeeded() {
        guard !welcomeShown, messages.isEmpty, connectionMode == .builtin else { return }
        welcomeShown = true

        let serverUrl = ServerConfig.shared.httpBaseURL
        Task {
            do {
                let url = URL(string: "\(serverUrl)/assistant/config")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let welcomeDict = json["welcomeMessage"] as? [String: String] {
                    let lang = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
                    let welcomeText = welcomeDict[lang] ?? welcomeDict["en"] ?? ""
                    if !welcomeText.isEmpty {
                        guard let convId = self.currentConversationId else { return }
                        let msg = ChatMessage(
                            conversationId: convId,
                            role: .assistant,
                            content: welcomeText
                        )
                        self.messages.insert(msg, at: 0)
                    }
                }
            } catch {
                // Fallback: use static welcome from L10n
                guard let convId = self.currentConversationId else { return }
                let welcomeText = L10n.tr("chat.welcome")
                let msg = ChatMessage(
                    conversationId: convId,
                    role: .assistant,
                    content: welcomeText
                )
                self.messages.insert(msg, at: 0)
            }
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
        // Resolve .agent to the real runtime mode based on agentId
        var resolvedMode = mode
        if mode == .agent {
            let agentId = try? await DatabaseService.shared.getSetting(key: ukey("agentId"))
            switch agentId {
            case "openclaw": resolvedMode = .openclaw
            case "copaw": resolvedMode = .copaw
            default: resolvedMode = .agent  // truly custom agents
            }
        }

        guard resolvedMode != connectionMode else { return }
        disconnect()
        resetStreamingState()
        connectionMode = resolvedMode
        Task {
            let key = currentUserId != "anonymous" ? "\(currentUserId):mode" : "mode"
            try? await DatabaseService.shared.setSetting(key: key, value: resolvedMode.rawValue)
        }
        await connect()
    }

    private func connectWebSocket() {
        var options = WebSocketService.ConnectOptions()

        Task {
            let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
            let apiKey = try? await DatabaseService.shared.getSetting(key: ukey("apiKey"))
            let deviceId = await getOrCreateDeviceId()

            options.authToken = authToken
            options.deviceId = deviceId

            if connectionMode == .copaw {
                let copawSubMode = try? await DatabaseService.shared.getSetting(key: ukey("copawSubMode"))
                let isCopawDeploy = copawSubMode == "deploy"
                // Deploy mode: no URL needed, server routes via bridge
                if !isCopawDeploy {
                    let copawUrl = try? await DatabaseService.shared.getSetting(key: ukey("copawUrl"))
                    let copawToken = try? await DatabaseService.shared.getSetting(key: ukey("copawToken"))
                    options.copawUrl = copawUrl
                    options.copawToken = copawToken
                }
            }

            if connectionMode == .builtin {
                let builtinSubMode = try? await DatabaseService.shared.getSetting(key: ukey("builtinSubMode"))
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
            let openclawUrl = try await DatabaseService.shared.getSetting(key: ukey("openclawUrl")) ?? ""
            let openclawToken = try await DatabaseService.shared.getSetting(key: ukey("openclawToken")) ?? ""

            if openclawUrl.isEmpty {
                // Empty URL: use WebSocket to server (server proxy mode for admin users)
                openclawProxyMode = true
                connectWebSocketForOpenClaw(
                    openclawUrl: openclawUrl,
                    openclawToken: openclawToken
                )
                return
            }
            openclawProxyMode = false

            openClawService.configure(url: openclawUrl, token: openclawToken)
            try await openClawService.ensureConnected()
            isConnected = true
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    /// Connect via WebSocket in OpenClaw mode (server proxy for admin users with empty URL)
    private func connectWebSocketForOpenClaw(openclawUrl: String, openclawToken: String) {
        Task {
            let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
            let deviceId = await getOrCreateDeviceId()

            var options = WebSocketService.ConnectOptions()
            options.authToken = authToken
            options.deviceId = deviceId
            options.openclawUrl = openclawUrl
            options.openclawToken = openclawToken

            wsService.connect(mode: .openclaw, options: options)
        }
    }

    /// Connect in unified agent mode
    /// Uses the real runtime mode (.openclaw / .copaw) based on agentId,
    /// so conversations and skills routing stay correctly isolated.
    private func connectAgent() async {
        do {
            let agentId = try await DatabaseService.shared.getSetting(key: ukey("agentId")) ?? "openclaw"
            let agentSubMode = try await DatabaseService.shared.getSetting(key: ukey("agentSubMode")) ?? "direct"
            let agentUrl = try await DatabaseService.shared.getSetting(key: ukey("agentUrl")) ?? ""
            let agentToken = try await DatabaseService.shared.getSetting(key: ukey("agentToken")) ?? ""

            // Resolve runtime mode from agentId (known agents get their real mode)
            let runtimeMode: ConnectionMode
            switch agentId {
            case "openclaw": runtimeMode = .openclaw
            case "copaw": runtimeMode = .copaw
            default: runtimeMode = .agent // truly custom agents
            }

            // Update connectionMode so conversation isolation and skills routing work correctly
            if connectionMode != runtimeMode {
                connectionMode = runtimeMode
            }

            // Direct + OpenClaw with URL: use OpenClawDirectService
            if agentSubMode == "direct" && agentId == "openclaw" && !agentUrl.isEmpty {
                openclawProxyMode = false
                openClawService.configure(url: agentUrl, token: agentToken)
                try await openClawService.ensureConnected()
                isConnected = true
                return
            }

            // Otherwise: connect via WS with agent fields
            openclawProxyMode = true

            let agentProtocol: String
            switch agentId {
            case "openclaw": agentProtocol = "openclaw-ws"
            case "copaw": agentProtocol = "ag-ui"
            default: agentProtocol = "openclaw-ws"
            }

            let authToken = try? await DatabaseService.shared.getSetting(key: "auth_token")
            let deviceId = await getOrCreateDeviceId()

            var options = WebSocketService.ConnectOptions()
            options.authToken = authToken
            options.deviceId = deviceId
            options.agentUrl = agentUrl.isEmpty ? nil : agentUrl
            options.agentToken = agentToken.isEmpty ? nil : agentToken
            options.agentProtocol = agentProtocol

            wsService.connect(mode: runtimeMode, options: options)
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func reconnect() {
        // Reset streaming state so UI is not stuck in "loading" after reconnect
        resetStreamingState()

        switch connectionMode {
        case .openclaw:
            if openclawProxyMode {
                wsService.reconnectNow()
            } else {
                openClawService.reconnectNow()
            }
        case .agent:
            // Agent mode: if using direct OpenClaw connection, reconnect that; otherwise WS
            if !openclawProxyMode {
                openClawService.reconnectNow()
            } else {
                wsService.reconnectNow()
            }
        case .byok:
            isConnected = true
        default:
            wsService.reconnectNow()
        }
    }

    // MARK: - Send Message

    func sendMessage(attachments: [Attachment]? = nil) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAttachments = attachments != nil && !(attachments!.isEmpty)
        guard (!text.isEmpty || hasAttachments), !isStreaming else { return }

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
                let titleText = text.isEmpty ? (attachments?.first?.name ?? "Attachment") : text
                updated.title = String(titleText.prefix(30))
            }
            updated.updatedAt = Int(Date().timeIntervalSince1970 * 1000)
            try await DatabaseService.shared.saveConversation(updated)
        } catch { /* ignore */ }

        // Add user message
        let userMsg = ChatMessage(
            conversationId: convId,
            role: .user,
            content: text,
            attachments: hasAttachments ? attachments : nil,
            isVault: isVaultMode
        )
        messages.append(userMsg)
        inputText = ""
        try? await DatabaseService.shared.saveMessage(userMsg)

        // Init streaming state
        graceRecoveryConversationId = nil
        graceRecoveryPartialAssistantId = nil
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
                history: history,
                attachments: hasAttachments ? attachments : nil
            )

        case .byok:
            await sendBYOK(text: text, convId: convId, history: history)

        case .agent:
            if openclawProxyMode {
                // WS proxy mode
                startStreamTimeout()
                wsService.sendChat(
                    conversationId: convId,
                    content: text,
                    history: history,
                    attachments: hasAttachments ? attachments : nil
                )
            } else {
                // Direct OpenClaw connection
                await sendOpenClaw(text: text, convId: convId)
            }

        case .openclaw:
            if openclawProxyMode {
                // Server proxy mode: route through WebSocket like builtin/copaw
                startStreamTimeout()
                wsService.sendChat(
                    conversationId: convId,
                    content: text,
                    history: history,
                    attachments: hasAttachments ? attachments : nil
                )
            } else {
                await sendOpenClaw(text: text, convId: convId)
            }
        }
    }

    // MARK: - Vault (Midong)

    func sendVaultPassword(password: String, confirmPassword: String? = nil, isSetup: Bool = false) {
        var payload: [String: Any] = ["password": password]
        if let confirmPassword {
            payload["confirmPassword"] = confirmPassword
        }
        payload["isSetup"] = isSetup

        let msg = WSMessage(type: .vaultPassword, payload: AnyCodable(payload))
        wsService.send(msg)
    }

    func lockVault() {
        isVaultMode = false
        messages.removeAll { $0.isVault }
    }

    // MARK: - Stop Generation

    func stopGeneration() {
        cancelStreamTimeout()

        if let convId = currentConversationId {
            switch connectionMode {
            case .builtin, .copaw:
                wsService.sendChatStop(conversationId: convId)
            case .agent:
                if openclawProxyMode {
                    wsService.sendChatStop(conversationId: convId)
                } else {
                    Task { await openClawService.abortChat() }
                }
            case .openclaw:
                if openclawProxyMode {
                    wsService.sendChatStop(conversationId: convId)
                } else {
                    Task { await openClawService.abortChat() }
                }
            case .byok:
                byokStreamTask?.cancel()
                byokStreamTask = nil
            }
        }

        graceRecoveryConversationId = nil
        graceRecoveryPartialAssistantId = nil
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
        graceRecoveryConversationId = nil
        graceRecoveryPartialAssistantId = nil
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

    // MARK: - Compare with Model

    func compareWithModel(originalContent: String, model: String, modelName: String) {
        guard !isStreaming, let convId = currentConversationId else { return }

        // Find the user message that preceded the assistant reply being compared
        // We search backwards for the last user message before the compare target
        let userContent: String = {
            // Find original assistant message, then look for user message before it
            if let idx = messages.lastIndex(where: { $0.content == originalContent && $0.role == .assistant }) {
                let preceding = messages[..<idx]
                if let userMsg = preceding.last(where: { $0.role == .user }) {
                    return userMsg.content
                }
            }
            return originalContent
        }()

        // Init streaming state
        graceRecoveryConversationId = nil
        graceRecoveryPartialAssistantId = nil
        let assistantId = UUID().uuidString
        currentAssistantId = assistantId
        streamBuffer = ""
        isStreaming = true
        streamingContent = nil

        // Build history (same as regular send)
        let history = buildHistory()

        // Send via WebSocket with model and compareMode
        startStreamTimeout()
        wsService.sendChat(
            conversationId: convId,
            content: userContent,
            history: history,
            model: model,
            compareMode: true
        )

        // Store compareModel so we can tag the resulting message
        self._pendingCompareModel = modelName
    }

    private var _pendingCompareModel: String?

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
            // Request skill list on connection (like Android does)
            wsService.send(WSMessage(type: .skillListRequest))
            showWelcomeIfNeeded()

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
                var parsedAttachments: [Attachment]?
                if let attArray = payload["attachments"] as? [[String: Any]] {
                    parsedAttachments = attArray.compactMap { dict -> Attachment? in
                        guard let id = dict["id"] as? String,
                              let typeStr = dict["type"] as? String,
                              let url = dict["url"] as? String,
                              let name = dict["name"] as? String,
                              let size = dict["size"] as? Int,
                              let mimeType = dict["mimeType"] as? String else { return nil }
                        return Attachment(
                            id: id,
                            type: Attachment.AttachmentType(rawValue: typeStr) ?? .file,
                            url: url,
                            name: name,
                            size: size,
                            mimeType: mimeType
                        )
                    }
                    if parsedAttachments?.isEmpty == true { parsedAttachments = nil }
                }
                // Extract backtest action from skillsInvoked
                var backtestAction: BacktestAction?
                if let skillsInvoked = payload["skillsInvoked"] as? [[String: Any]] {
                    for si in skillsInvoked {
                        if let output = si["output"] as? [String: Any],
                           let actionDict = output["open_backtest_workstation"] as? [String: Any] {
                            backtestAction = BacktestAction(
                                label: actionDict["label"] as? String ?? "在回测助手查看完整分析",
                                stockCode: actionDict["stock_code"] as? String ?? "",
                                strategyId: actionDict["strategy_id"] as? String
                            )
                            break
                        }
                    }
                }
                handleStreamDone(fullContent: fullContent, conversationId: convId, attachments: parsedAttachments, backtestAction: backtestAction)
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

        case .vaultPasswordRequest:
            if let payload = message.payload?.dictValue {
                isVaultSetup = (payload["isFirstTime"] as? Bool) == true
                showVaultPassword = true
            }

        case .vaultUnlocked:
            isVaultMode = true
            showVaultPassword = false
            if let payload = message.payload?.dictValue,
               let msg = payload["message"] as? String,
               let convId = currentConversationId {
                let vaultMsg = ChatMessage(
                    conversationId: convId,
                    role: .assistant,
                    content: msg,
                    isVault: true
                )
                messages.append(vaultMsg)
                Task { try? await DatabaseService.shared.saveMessage(vaultMsg) }
            }

        case .vaultLocked:
            isVaultMode = false
            vaultClosePending = true
            // Remove vault messages from the in-memory list
            messages.removeAll { $0.isVault }

        case .error:
            if let payload = message.payload?.dictValue {
                let code = payload["code"] as? String ?? ""
                let msg = payload["message"] as? String ?? "Unknown error"

                if code == "CONNECTION_CLOSED" {
                    isConnected = false
                    // Mark for grace recovery if we were streaming
                    if let aid = currentAssistantId {
                        graceRecoveryConversationId = currentConversationId
                        graceRecoveryPartialAssistantId = streamBuffer.isEmpty ? nil : aid
                    }
                    // Save any partial streaming content before resetting
                    if let assistantId = currentAssistantId, !streamBuffer.isEmpty,
                       let convId = currentConversationId {
                        let msg = ChatMessage(
                            id: assistantId,
                            conversationId: convId,
                            role: .assistant,
                            content: streamBuffer
                        )
                        messages.append(msg)
                        Task { try? await DatabaseService.shared.saveMessage(msg) }
                    }
                    cancelStreamTimeout()
                    resetStreamingState()
                    return
                }

                // Vault-specific errors: show in password sheet context (don't dismiss)
                if code == "VAULT_WRONG_PASSWORD" || code == "VAULT_LOCKED_OUT" || code == "VAULT_ERROR" {
                    errorMessage = msg
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        if self.errorMessage == msg { self.errorMessage = nil }
                    }
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
        // Grace period recovery: auto-init streaming when server flushes buffered content
        if currentAssistantId == nil,
           let graceConvId = graceRecoveryConversationId,
           graceConvId == currentConversationId {
            if let partialId = graceRecoveryPartialAssistantId,
               let partial = messages.first(where: { $0.id == partialId }) {
                // Reuse partial message ID, recover its content
                currentAssistantId = partial.id
                streamBuffer = partial.content
                messages.removeAll { $0.id == partial.id }
            } else {
                currentAssistantId = UUID().uuidString
                streamBuffer = ""
            }
            isStreaming = true
        }
        guard currentAssistantId != nil else { return }
        streamBuffer += delta

        let now = Date()
        if now.timeIntervalSince(lastStreamUpdate) > streamThrottleInterval {
            streamingContent = streamBuffer
            lastStreamUpdate = now
        }
    }

    private func handleStreamDone(fullContent: String, conversationId: String, attachments: [Attachment]? = nil, backtestAction: BacktestAction? = nil) {
        if let assistantId = currentAssistantId {
            let compareModel = _pendingCompareModel
            _pendingCompareModel = nil

            // If vault just closed, mark this response as vault too so it gets cleaned up
            let markAsVault = isVaultMode || vaultClosePending
            if vaultClosePending {
                vaultClosePending = false
            }

            let msg = ChatMessage(
                id: assistantId,
                conversationId: conversationId,
                role: .assistant,
                content: fullContent,
                attachments: attachments,
                compareModel: compareModel,
                isVault: markAsVault,
                backtestAction: backtestAction
            )

            if markAsVault && !isVaultMode {
                // Vault closed: don't show this message, don't persist it
                resetStreamingState()
                return
            }

            messages.append(msg)
            Task {
                try? await DatabaseService.shared.saveMessage(msg)
                await checkAndCleanup(conversationId: conversationId)
            }

            graceRecoveryConversationId = nil
            graceRecoveryPartialAssistantId = nil
            resetStreamingState()
        } else if let graceConvId = graceRecoveryConversationId, graceConvId == conversationId {
            // Grace recovery: CHAT_DONE without preceding chunks (edge case)
            if !fullContent.isEmpty {
                if let partialId = graceRecoveryPartialAssistantId,
                   let idx = messages.firstIndex(where: { $0.id == partialId }) {
                    // Update partial message with complete content
                    messages[idx] = ChatMessage(
                        id: partialId,
                        conversationId: conversationId,
                        role: .assistant,
                        content: fullContent,
                        attachments: attachments
                    )
                    let updated = messages[idx]
                    Task {
                        try? await DatabaseService.shared.saveMessage(updated)
                    }
                } else {
                    let msg = ChatMessage(
                        conversationId: conversationId,
                        role: .assistant,
                        content: fullContent,
                        attachments: attachments
                    )
                    messages.append(msg)
                    Task { try? await DatabaseService.shared.saveMessage(msg) }
                }
            }
            graceRecoveryConversationId = nil
            graceRecoveryPartialAssistantId = nil
            resetStreamingState()
        }
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
        _pendingCompareModel = nil
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
        return recent.map { ChatHistoryItem(role: $0.role.rawValue, content: $0.content, attachments: $0.attachments) }
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
