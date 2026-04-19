import Foundation
import Network

/// Connection state for the WebSocket service.
enum WSConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(sessionId: String)
    case reconnecting(attempt: Int)
}

/// WebSocket client for AgentOS server protocol.
/// Uses URLSessionWebSocketTask with adaptive heartbeat, exponential backoff reconnection,
/// and network change detection.
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

    // Adaptive heartbeat
    private let networkMonitor = NWPathMonitor()
    private var currentNetworkType: NWInterface.InterfaceType = .wifi
    private var rttHistory: [TimeInterval] = []
    private var lastPingSentAt: Date?
    private var pongMissCount = 0

    /// Ping interval: 10s on cellular (keep NAT alive), 25s on WiFi.
    private var pingInterval: TimeInterval {
        currentNetworkType == .cellular ? 10.0 : 25.0
    }

    /// Pong timeout: adapts to measured RTT; more generous on cellular.
    private var pongTimeout: TimeInterval {
        if rttHistory.count >= 3 {
            let recent = Array(rttHistory.suffix(10))
            let avg = recent.reduce(0, +) / Double(recent.count)
            return min(max(avg * 3, 5.0), 20.0)
        }
        return currentNetworkType == .cellular ? 20.0 : 15.0
    }

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
        startNetworkMonitor()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newType: NWInterface.InterfaceType
                if path.usesInterfaceType(.wifi) {
                    newType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    newType = .cellular
                } else {
                    newType = .other
                }
                if newType != self.currentNetworkType {
                    print("[WS] Network changed: \(self.currentNetworkType) → \(newType)")
                    self.currentNetworkType = newType
                    self.rttHistory.removeAll()
                    // Reconnect immediately on network change
                    if !self.intentionalDisconnect, let mode = self.lastMode {
                        self.connect(mode: mode, options: self.lastOptions ?? ConnectOptions())
                    }
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "ws.network"))
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

    func sendChat(conversationId: String, content: String, history: [ChatHistoryItem]? = nil, attachments: [Attachment]? = nil, model: String? = nil) {
        var dict = encodeToDictionary(ChatSendPayload(conversationId: conversationId, content: content, history: history, model: model))
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

        // Re-read from ServerConfig in case it was updated after init
        let currentURL = ServerConfig.shared.wsURL
        if currentURL != serverURL {
            serverURL = currentURL
        }

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

        // Handle PONG — cancel deadline and track RTT
        if message.type == .pong {
            pongDeadlineTask?.cancel()
            pongDeadlineTask = nil
            pongMissCount = 0
            if let sentAt = lastPingSentAt {
                let rtt = Date().timeIntervalSince(sentAt)
                rttHistory.append(rtt)
                if rttHistory.count > 20 { rttHistory.removeFirst() }
            }
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

    // MARK: - Adaptive Heartbeat

    private func startPing() {
        stopPing()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let interval = await MainActor.run { self.pingInterval }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await MainActor.run { self.sendPingWithDeadline() }
            }
        }
    }

    /// Send a ping and set an adaptive pong deadline. On first timeout, retries once.
    private func sendPingWithDeadline() {
        lastPingSentAt = Date()
        send(WSMessage(type: .ping))

        let timeout = pongTimeout
        pongDeadlineTask?.cancel()
        pongDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                if self.pongMissCount < 1 {
                    // First timeout: retry once before giving up
                    self.pongMissCount += 1
                    print("[WS] Pong timeout (\(Int(timeout))s) — retry ping")
                    self.sendPingWithDeadline()
                } else {
                    // Second consecutive timeout: close connection
                    print("[WS] Pong timeout after retry — closing connection")
                    self.pongMissCount = 0
                    self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                }
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        pongDeadlineTask?.cancel()
        pongDeadlineTask = nil
        pongMissCount = 0
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
