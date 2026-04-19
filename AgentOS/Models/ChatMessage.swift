import Foundation
import GRDB

/// Action data for "open backtest workstation" buttons in chat bubbles
struct BacktestAction: Sendable, Equatable {
    let label: String
    let stockCode: String
    let strategyId: String?
}

struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let timestamp: Int
    var skillName: String?
    var attachments: [Attachment]?
    var isVault: Bool
    /// Transient (not persisted): action button to open backtest workstation
    var backtestAction: BacktestAction?

    enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
    }

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: MessageRole,
        content: String,
        timestamp: Int = Int(Date().timeIntervalSince1970 * 1000),
        skillName: String? = nil,
        attachments: [Attachment]? = nil,
        isVault: Bool = false,
        backtestAction: BacktestAction? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.skillName = skillName
        self.attachments = attachments
        self.isVault = isVault
        self.backtestAction = backtestAction
    }
}

// MARK: - GRDB

extension ChatMessage: FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case timestamp
        case skillName = "skill_name"
        case attachments
        case isVault = "is_vault"
    }

    init(row: Row) throws {
        id = row["id"]
        conversationId = row["conversation_id"]
        role = MessageRole(rawValue: row["role"]) ?? .assistant
        content = row["content"]
        timestamp = row["timestamp"]
        skillName = row["skill_name"]
        isVault = (row["is_vault"] as Int?) == 1

        if let jsonString: String = row["attachments"],
           let data = jsonString.data(using: .utf8) {
            attachments = try? JSONDecoder().decode([Attachment].self, from: data)
        } else {
            attachments = nil
        }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["conversation_id"] = conversationId
        container["role"] = role.rawValue
        container["content"] = content
        container["timestamp"] = timestamp
        container["skill_name"] = skillName
        container["is_vault"] = isVault ? 1 : 0

        if let attachments = attachments {
            let data = try JSONEncoder().encode(attachments)
            container["attachments"] = String(data: data, encoding: .utf8)
        } else {
            container["attachments"] = nil as String?
        }
    }
}
