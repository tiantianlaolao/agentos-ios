import Foundation

/// Connection state for the WebSocket service.
enum WSConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(sessionId: String)
    case reconnecting(attempt: Int)
}

/// WebSocket client for AgentOS server protocol.
/// Uses URLSessionWebSocketTask with exponential backoff reconnection and heartbeat.
@MainActor
@Observable
final class WebSocketService {
    // MARK: - Public state

    var connectionState: WSConnectionState = .disconnected

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    // MARK: - Configuration

    private var defaultURL: String { ServerConfig.shared.wsURL }
    private var serverURL: String

    // MARK: - Private state

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var pongDeadlineTask: Task<Void, Never>?

    private var lastMode: ConnectionMode?
    private var lastOptions: ConnectOptions?
    private var intentionalDisconnect = false

    private var messageHandlers: [(WSMessage) -> Void] = []

    struct ConnectOptions: Sendable {
        var provider: LLMProvider?
        var apiKey: String?
        var openclawUrl: String?
        var openclawToken: String?
        var copawUrl: String?
        var copawToken: String?
        var authToken: String?
        var model: String?
        var deviceId: String?
        var agentUrl: String?
        var agentToken: String?
        var agentProtocol: String?
    }

    // MARK: - Init

    init(url: String? = nil) {
        self.serverURL = url ?? ServerConfig.shared.wsURL
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Public API

    func onMessage(_ handler: @escaping @Sendable (WSMessage) -> Void) {
        messageHandlers.append(handler)
    }

    func connect(mode: ConnectionMode, options: ConnectOptions = ConnectOptions()) {
        lastMode = mode
        lastOptions = options
        intentionalDisconnect = false
        reconnectAttempts = 0
        performConnect(mode: mode, options: options)
    }

    func disconnect() {
        intentionalDisconnect = true
        cleanup()
        connectionState = .disconnected
    }

    func send(_ message: WSMessage) {
        guard let task = webSocketTask else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { error in
            if let error {
                print("[WS] Send error: \(error.localizedDescription)")
            }
        }
    }

    func sendChat(conversationId: String, content: String, history: [ChatHistoryItem]? = nil, attachments: [Attachment]? = nil, model: String? = nil, compareMode: Bool? = nil) {
        var dict = encodeToDictionary(ChatSendPayload(conversationId: conversationId, content: content, history: history, model: model, compareMode: compareMode))
        if let attachments = attachments, !attachments.isEmpty {
            let attachmentDicts = attachments.map { att -> [String: Any] in
                [
                    "id": att.id,
                    "type": att.type.rawValue,
                    "url": att.url,
                    "name": att.name,
                    "size": att.size,
                    "mimeType": att.mimeType
                ]
            }
            dict["attachments"] = attachmentDicts
        }
        let msg = WSMessage(type: .chatSend, payload: AnyCodable(dict))
        send(msg)
    }

    func sendChatStop(conversationId: String) {
        let payload = ChatStopPayload(conversationId: conversationId)
        let msg = WSMessage(type: .chatStop, payload: AnyCodable(encodeToDictionary(payload)))
        send(msg)
    }

    func reconnectNow() {
        guard !isConnected, let mode = lastMode else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        performConnect(mode: mode, options: lastOptions ?? ConnectOptions())
    }

    // MARK: - Connection lifecycle

    private func performConnect(mode: ConnectionMode, options: ConnectOptions) {
        cleanup()
        connectionState = .connecting

        guard let url = URL(string: serverURL) else {
            print("[WS] Invalid URL: \(serverURL)")
            return
        }

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Send CONNECT message
        let connectPayload = ConnectPayload(
            mode: mode,
            provider: options.provider,
            apiKey: options.apiKey,
            openclawUrl: options.openclawUrl,
            openclawToken: options.openclawToken,
            copawUrl: options.copawUrl,
            copawToken: options.copawToken,
            deviceId: options.deviceId,
            authToken: options.authToken,
            model: options.model,
            agentUrl: options.agentUrl,
            agentToken: options.agentToken,
            agentProtocol: options.agentProtocol
        )
        let connectMsg = WSMessage(
            type: .connect,
            payload: AnyCodable(encodeToDictionary(connectPayload))
        )
        send(connectMsg)

        // Start receiving
        startReceiving()
        // Start heartbeat
        startPing()
    }

    private func startReceiving() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = await MainActor.run(body: { self.webSocketTask }) else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self.handleTextMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleTextMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        await self.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let message = try? decoder.decode(WSMessage.self, from: data) else {
            print("[WS] Failed to decode message")
            return
        }

        // Handle PONG — cancel deadline
        if message.type == .pong {
            pongDeadlineTask?.cancel()
            pongDeadlineTask = nil
        }

        // Handle connected
        if message.type == .connected {
            reconnectAttempts = 0
            if let payloadDict = message.payload?.dictValue,
               let sessionId = payloadDict["sessionId"] as? String {
                connectionState = .connected(sessionId: sessionId)
            } else {
                connectionState = .connected(sessionId: "")
            }
        }

        // Dispatch to handlers
        for handler in messageHandlers {
            handler(message)
        }
    }

    private func handleDisconnect() {
        guard !intentionalDisconnect else { return }
        stopPing()

        // Notify handlers about disconnect
        let errorMsg = WSMessage(
            type: .error,
            payload: AnyCodable(["code": "CONNECTION_CLOSED", "message": "Reconnecting..."])
        )
        for handler in messageHandlers {
            handler(errorMsg)
        }

        scheduleReconnect()
    }

    // MARK: - Heartbeat

    private func startPing() {
        stopPing()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled, let self else { break }
                let pingMsg = WSMessage(type: .ping)
                await MainActor.run { self.send(pingMsg) }

                // Set pong deadline
                await MainActor.run {
                    self.pongDeadlineTask?.cancel()
                    self.pongDeadlineTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(15))
                        guard !Task.isCancelled, let self else { return }
                        print("[WS] Pong timeout — closing connection")
                        await MainActor.run {
                            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        }
                    }
                }
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        pongDeadlineTask?.cancel()
        pongDeadlineTask = nil
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard let mode = lastMode else { return }
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)

        print("[WS] Reconnecting in \(delay)s (attempt \(reconnectAttempts))...")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self, delay] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.performConnect(mode: mode, options: self.lastOptions ?? ConnectOptions())
            }
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        stopPing()
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Helpers

    private func encodeToDictionary<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
