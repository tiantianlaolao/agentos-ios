import Foundation

// MARK: - MessageType

/// AgentOS WebSocket Protocol v1 message types.
/// Mirrors server/src/types/protocol.ts
enum MessageType: String, Codable, Sendable {
    // Client -> Server
    case connect = "connect"
    case chatSend = "chat.send"
    case chatStop = "chat.stop"
    case skillListRequest = "skill.list.request"
    case skillToggle = "skill.toggle"
    case skillInstall = "skill.install"
    case skillUninstall = "skill.uninstall"
    case skillLibraryRequest = "skill.library.request"
    case skillConfigGet = "skill.config.get"
    case skillConfigSet = "skill.config.set"

    // Server -> Client
    case connected = "connected"
    case chatChunk = "chat.chunk"
    case chatDone = "chat.done"
    case skillStart = "skill.start"
    case skillResult = "skill.result"
    case pushMessage = "push.message"
    case skillListResponse = "skill.list.response"
    case skillLibraryResponse = "skill.library.response"
    case skillConfigResponse = "skill.config.response"
    case error = "error"

    // Bidirectional
    case ping = "ping"
    case pong = "pong"
}

// MARK: - ConnectionMode

enum ConnectionMode: String, Codable, Sendable, CaseIterable {
    case builtin
    case openclaw
    case copaw
    case byok
    case agent
}

// MARK: - LLMProvider

enum LLMProvider: String, Codable, Sendable, CaseIterable {
    case deepseek
    case openai
    case anthropic
    case gemini
    case moonshot
    case qwen
    case zhipu
    case openrouter
}

// MARK: - ErrorCode

enum ErrorCode: String, Codable, Sendable {
    case invalidMessage = "INVALID_MESSAGE"
    case authFailed = "AUTH_FAILED"
    case rateLimited = "RATE_LIMITED"
    case providerError = "PROVIDER_ERROR"
    case skillError = "SKILL_ERROR"
    case openclawDisconnected = "OPENCLAW_DISCONNECTED"
    case internalError = "INTERNAL_ERROR"
}

// MARK: - WebSocket Messages (JSON Codable)

struct WSMessage: Codable, Sendable {
    let id: String
    let type: MessageType
    let timestamp: Int
    let payload: AnyCodable?

    init(type: MessageType, payload: AnyCodable? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Int(Date().timeIntervalSince1970 * 1000)
        self.payload = payload
    }

    init(id: String, type: MessageType, timestamp: Int, payload: AnyCodable?) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }
}

// MARK: - Payload Types

struct ConnectPayload: Codable, Sendable {
    let mode: ConnectionMode
    var provider: LLMProvider?
    var apiKey: String?
    var openclawUrl: String?
    var openclawToken: String?
    var copawUrl: String?
    var copawToken: String?
    var deviceId: String?
    var authToken: String?
    var model: String?
    var agentUrl: String?
    var agentToken: String?
    var agentProtocol: String?
}

struct ConnectedPayload: Codable, Sendable {
    let sessionId: String
    let mode: ConnectionMode
    let skills: [String]
}

struct ChatSendPayload: Codable, Sendable {
    let conversationId: String
    let content: String
    var history: [ChatHistoryItem]?
    var attachments: [Attachment]?
    var model: String?
    var compareMode: Bool?
}

struct ChatStopPayload: Codable, Sendable {
    let conversationId: String
}

struct ChatChunkPayload: Codable, Sendable {
    let conversationId: String
    let delta: String
}

struct ChatDonePayload: Codable, Sendable {
    let conversationId: String
    let fullContent: String
    var usage: TokenUsage?
    var skillsInvoked: [SkillInvocation]?
    var attachments: [Attachment]?
}

struct SkillStartPayload: Codable, Sendable {
    let conversationId: String
    let skillName: String
    let description: String
}

struct SkillResultPayload: Codable, Sendable {
    let conversationId: String
    let skillName: String
    let success: Bool
    var data: AnyCodable?
    var error: String?
}

struct PushMessagePayload: Codable, Sendable {
    let content: String
    let source: String
}

struct ErrorPayload: Codable, Sendable {
    let code: ErrorCode
    let message: String
    var conversationId: String?
}

struct SkillTogglePayload: Codable, Sendable {
    let skillName: String
    let enabled: Bool
}

struct SkillInstallPayload: Codable, Sendable {
    let skillName: String
}

struct SkillLibraryRequestPayload: Codable, Sendable {
    var category: String?
    var search: String?
    var environment: String?
}

struct SkillConfigGetPayload: Codable, Sendable {
    let skillName: String
}

struct SkillConfigSetPayload: Codable, Sendable {
    let skillName: String
    let config: [String: AnyCodable]
}

struct SkillConfigResponsePayload: Codable, Sendable {
    let skillName: String
    let config: [String: AnyCodable]
    let fields: [SkillConfigField]
}

struct SkillConfigField: Codable, Sendable, Identifiable {
    let key: String
    let label: String
    let type: String
    var required: Bool?
    var secret: Bool?
    var description: String?

    var id: String { key }
}

// MARK: - Attachment

struct Attachment: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let type: AttachmentType
    let url: String
    let name: String
    let size: Int
    let mimeType: String

    enum AttachmentType: String, Codable, Sendable {
        case image
        case file
    }
}

// MARK: - Supporting Types

struct ChatHistoryItem: Codable, Sendable {
    let role: String
    let content: String
    var attachments: [Attachment]?
}

struct TokenUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
}

struct SkillInvocation: Codable, Sendable {
    let name: String
    let input: AnyCodable
    let output: AnyCodable
}

struct SkillFunction: Codable, Sendable, Identifiable {
    let name: String
    let description: String

    var id: String { name }
}

// MARK: - AnyCodable (type-erased Codable wrapper)

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var doubleValue: Double? { value as? Double }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
}
