import Foundation
import CryptoKit

/// Tool event from OpenClaw Gateway agent execution.
struct ToolEvent {
    let phase: String  // "start", "result", "error"
    let name: String
    var argsJSON: String?
    var resultJSON: String?
}

/// Direct WebSocket connection to OpenClaw Gateway.
/// Implements Gateway WS protocol v3 with challenge-response Ed25519 auth.
@MainActor
@Observable
final class OpenClawDirectService {
    // MARK: - Public state

    var isConnected = false
    var pairingError: String?

    // MARK: - Callbacks

    var onChunk: ((String) -> Void)?
    var onDone: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolEvent: ((ToolEvent) -> Void)?
    var onPush: ((String) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    // MARK: - Private state

    private var webSocketTask: URLSessionWebSocketTask?
    private var session = URLSession(configuration: .default)
    private var wsUrl: String = ""
    private var token: String = ""
    private var sessionKey = "agentos-session"

    private var connected = false
    private var autoReconnect = true
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // Pending request/response tracking — uses Data (Sendable) to avoid crossing actor boundary issues
    private var pendingContinuations: [String: UnsafeContinuation<Data, Error>] = [:]

    // Streaming state
    private var fullContent = ""
    private var streamingActive = false

    // Push message accumulators
    private var pushAccumulators: [String: String] = [:]

    // Device identity
    private let identityService = DeviceIdentityService.shared

    // MARK: - Public API

    func configure(url: String, token: String) {
        self.token = token
        // Normalize URL to ws://
        var normalized = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasPrefix("http://") {
            normalized = "ws://" + normalized.dropFirst(7)
        } else if normalized.hasPrefix("https://") {
            normalized = "wss://" + normalized.dropFirst(8)
        }
        self.wsUrl = normalized
    }

    func ensureConnected() async throws {
        if connected, webSocketTask != nil { return }
        try await performConnect()
    }

    func disconnect() {
        autoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connected = false
        isConnected = false
        streamingActive = false

        for (_, continuation) in pendingContinuations {
            continuation.resume(throwing: OpenClawError.disconnected)
        }
        pendingContinuations.removeAll()
        pushAccumulators.removeAll()
        pairingError = nil

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        onConnectionChange?(false)
    }

    func sendChat(content: String) async {
        do {
            try await ensureConnected()
        } catch {
            onError?(error.localizedDescription)
            return
        }

        fullContent = ""
        streamingActive = true

        let idempotencyKey = UUID().uuidString

        // Send chat.send request — the actual streaming data arrives via the receive loop
        do {
            _ = try await request(method: "chat.send", params: [
                "sessionKey": sessionKey,
                "message": content,
                "idempotencyKey": idempotencyKey,
                "timeoutMs": 120000
            ] as [String: Any])
        } catch {
            if streamingActive {
                streamingActive = false
                onError?(error.localizedDescription)
            }
        }
    }

    func abortChat() async {
        do {
            _ = try await request(method: "chat.abort", params: ["sessionKey": sessionKey])
        } catch {
            // Ignore abort errors
        }
    }

    /// Skill info returned from Gateway's skills.status method.
    struct GatewaySkill: Sendable {
        let name: String
        let description: String
        var emoji: String?
        var eligible: Bool?
        var disabled: Bool?
        var source: String?
    }

    func listSkills() async -> [GatewaySkill] {
        do {
            try await ensureConnected()
            let result = try await request(method: "skills.status", params: [:])
            guard let skills = result["skills"] as? [[String: Any]] else { return [] }
            return skills.map { s in
                GatewaySkill(
                    name: s["name"] as? String ?? "",
                    description: s["description"] as? String ?? "",
                    emoji: s["emoji"] as? String,
                    eligible: s["eligible"] as? Bool,
                    disabled: s["disabled"] as? Bool,
                    source: s["source"] as? String
                )
            }
        } catch {
            print("[OpenClaw Direct] listSkills failed: \(error.localizedDescription)")
            return []
        }
    }

    func reconnectNow() {
        guard !connected else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        autoReconnect = true
        Task {
            try? await ensureConnected()
        }
    }

    // MARK: - Connection

    private func performConnect() async throws {
        guard let url = URL(string: wsUrl) else {
            throw OpenClawError.invalidURL
        }

        // Clean up previous connection
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        connected = false

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Start receive loop
        startReceiving()

        // Wait for challenge-response handshake to complete
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectContinuation = continuation

            // Timeout
            Task {
                try? await Task.sleep(for: .seconds(15))
                if let cont = self.connectContinuation {
                    self.connectContinuation = nil
                    cont.resume(throwing: OpenClawError.connectionTimeout)
                }
            }
        }
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
                        await self.handleRawMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleRawMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        await self.handleClose()
                    }
                    break
                }
            }
        }
    }

    // MARK: - Message handling

    private func handleRawMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = msg["type"] as? String

        // Event frames
        if type == "event" || (type == nil && msg["event"] != nil) {
            handleEvent(msg)
            return
        }

        // Response frames
        if type == "res" {
            handleResponse(msg)
            return
        }
    }

    private func handleEvent(_ msg: [String: Any]) {
        let eventName = msg["event"] as? String ?? ""
        let payload = msg["payload"] as? [String: Any] ?? [:]

        // Challenge-response auth
        if eventName == "connect.challenge" {
            handleChallenge(payload: payload)
            return
        }

        // Agent events — text deltas + tool events
        if eventName == "agent" {
            let stream = payload["stream"] as? String
            let agentSessionKey = payload["sessionKey"] as? String

            if stream == "assistant" && matchSessionKey(agentSessionKey) {
                if let agentData = payload["data"] as? [String: Any],
                   let delta = agentData["delta"] as? String {
                    fullContent += delta
                    onChunk?(delta)
                }
            }

            if stream == "tool" {
                if let toolData = payload["data"] as? [String: Any] {
                    var argsJSON: String?
                    if let args = toolData["args"] {
                        argsJSON = (try? JSONSerialization.data(withJSONObject: args))
                            .flatMap { String(data: $0, encoding: .utf8) }
                    }
                    var resultJSON: String?
                    if let result = toolData["result"] {
                        resultJSON = (try? JSONSerialization.data(withJSONObject: result))
                            .flatMap { String(data: $0, encoding: .utf8) }
                    }
                    let event = ToolEvent(
                        phase: toolData["phase"] as? String ?? "",
                        name: toolData["name"] as? String ?? "",
                        argsJSON: argsJSON,
                        resultJSON: resultJSON
                    )
                    onToolEvent?(event)
                }
            }
        }

        // Chat state events
        if eventName == "chat" {
            let chatSessionKey = payload["sessionKey"] as? String
            let state = payload["state"] as? String ?? ""

            if matchSessionKey(chatSessionKey) {
                if state == "final" || state == "aborted" {
                    streamingActive = false
                    onDone?(fullContent)
                } else if state == "error" {
                    streamingActive = false
                    let errorMessage = payload["errorMessage"] as? String ?? "Chat error"
                    onError?(errorMessage)
                }
            }

            // Push messages from cron/scheduled sessions
            let isUserSession = chatSessionKey?.contains("agentos-") ?? false
            if !matchSessionKey(chatSessionKey) && !isUserSession {
                let runKey = (payload["runId"] as? String) ?? chatSessionKey ?? "unknown"
                if state == "delta" {
                    if let pmsg = payload["message"] as? [String: Any],
                       let content = pmsg["content"] as? [[String: Any]] {
                        let text = content.filter { ($0["type"] as? String) == "text" }
                            .compactMap { $0["text"] as? String }
                            .joined()
                        pushAccumulators[runKey] = text
                    }
                } else if state == "final" {
                    var text = pushAccumulators[runKey] ?? ""
                    if let pmsg = payload["message"] as? [String: Any],
                       let content = pmsg["content"] as? [[String: Any]] {
                        text = content.filter { ($0["type"] as? String) == "text" }
                            .compactMap { $0["text"] as? String }
                            .joined()
                    }
                    if !text.isEmpty {
                        onPush?(text)
                    }
                    pushAccumulators.removeValue(forKey: runKey)
                }
            }
        }
    }

    private func handleChallenge(payload: [String: Any]) {
        do {
            let key = try identityService.loadOrCreateKeyPair()
            let devId = identityService.deviceId(for: key)
            let nonce = payload["nonce"] as? String
            let role = "operator"
            let scopes = ["operator.admin", "operator.write"]
            let clientId = "gateway-client"
            let clientMode = "backend"
            let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
            let authToken: String? = token.isEmpty ? nil : token

            let authPayload = identityService.buildAuthPayload(
                deviceId: devId,
                clientId: clientId,
                clientMode: clientMode,
                role: role,
                scopes: scopes,
                signedAtMs: signedAtMs,
                token: authToken,
                nonce: nonce
            )

            let signature = try identityService.sign(
                data: Data(authPayload.utf8),
                with: key
            )

            var connectParams: [String: Any] = [
                "minProtocol": 3,
                "maxProtocol": 3,
                "role": role,
                "scopes": scopes,
                "client": [
                    "id": clientId,
                    "platform": "ios",
                    "mode": clientMode,
                    "version": "0.1.0"
                ],
                "device": [
                    "id": devId,
                    "publicKey": identityService.publicKeyBase64Url(for: key),
                    "signature": signature,
                    "signedAt": signedAtMs,
                    "nonce": nonce as Any
                ]
            ]

            if let authToken, !authToken.isEmpty {
                connectParams["auth"] = ["token": authToken]
            } else {
                connectParams["auth"] = [String: Any]()
            }

            let frame: [String: Any] = [
                "type": "req",
                "id": UUID().uuidString,
                "method": "connect",
                "params": connectParams
            ]

            sendRaw(frame)
        } catch {
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
        }
    }

    private func handleResponse(_ msg: [String: Any]) {
        let id = msg["id"] as? String ?? ""
        let ok = msg["ok"] as? Bool ?? false

        // Connection handshake response
        if !connected {
            if ok {
                connected = true
                isConnected = true
                onConnectionChange?(true)
                connectContinuation?.resume()
                connectContinuation = nil
            } else {
                let err = msg["error"] as? [String: Any]
                let errCode = err?["code"] as? String
                let errMessage = err?["message"] as? String ?? "Gateway connect failed"

                if errCode == "NOT_PAIRED" {
                    let pairingMsg = "Device not yet paired. Please approve this device in the OpenClaw Control UI or Telegram bot, then retry."
                    pairingError = pairingMsg
                    connectContinuation?.resume(throwing: OpenClawError.notPaired(pairingMsg))
                } else {
                    connectContinuation?.resume(throwing: OpenClawError.connectionFailed(errMessage))
                }
                connectContinuation = nil
            }
            return
        }

        // Normal request/response
        if let continuation = pendingContinuations.removeValue(forKey: id) {
            if ok {
                let payload = msg["payload"] as? [String: Any] ?? [:]
                let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                continuation.resume(returning: data)
            } else {
                let err = msg["error"] as? [String: Any]
                let errMessage = err?["message"] as? String ?? "Request failed"
                continuation.resume(throwing: OpenClawError.requestFailed(errMessage))
            }
        }
    }

    private func handleClose() {
        connected = false
        isConnected = false
        webSocketTask = nil
        onConnectionChange?(false)

        for (_, continuation) in pendingContinuations {
            continuation.resume(throwing: OpenClawError.disconnected)
        }
        pendingContinuations.removeAll()

        connectContinuation?.resume(throwing: OpenClawError.disconnected)
        connectContinuation = nil

        // Auto-reconnect
        if autoReconnect {
            reconnectTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                print("[OpenClaw Direct] Reconnecting...")
                try? await self.ensureConnected()
            }
        }
    }

    // MARK: - Request/Response

    @discardableResult
    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard webSocketTask != nil else {
            throw OpenClawError.disconnected
        }

        let id = UUID().uuidString

        let data: Data = try await withUnsafeThrowingContinuation { continuation in
            pendingContinuations[id] = continuation

            let frame: [String: Any] = [
                "type": "req",
                "id": id,
                "method": method,
                "params": params
            ]
            sendRaw(frame)

            // Timeout
            Task {
                try? await Task.sleep(for: .seconds(120))
                if let cont = self.pendingContinuations.removeValue(forKey: id) {
                    cont.resume(throwing: OpenClawError.requestTimeout(method))
                }
            }
        }

        // Convert Data back to dictionary
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Helpers

    private func matchSessionKey(_ key: String?) -> Bool {
        guard let key else { return false }
        if key == sessionKey { return true }
        let stripped = key.replacingOccurrences(of: "agent:main:", with: "")
        return stripped == sessionKey
    }

    private func sendRaw(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("[OpenClaw Direct] Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Errors

    enum OpenClawError: Error, LocalizedError {
        case invalidURL
        case connectionTimeout
        case connectionFailed(String)
        case notPaired(String)
        case disconnected
        case requestFailed(String)
        case requestTimeout(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Gateway URL"
            case .connectionTimeout: return "Gateway connection timeout"
            case .connectionFailed(let msg): return msg
            case .notPaired(let msg): return msg
            case .disconnected: return "Gateway disconnected"
            case .requestFailed(let msg): return msg
            case .requestTimeout(let method): return "Request \(method) timed out"
            }
        }
    }
}
