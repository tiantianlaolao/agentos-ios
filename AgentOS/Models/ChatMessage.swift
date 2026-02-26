import Foundation
import GRDB

struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let timestamp: Int
    var skillName: String?

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
        skillName: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.skillName = skillName
    }
}

// MARK: - GRDB

extension ChatMessage: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "messages"

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case timestamp
        case skillName = "skill_name"
    }
}
