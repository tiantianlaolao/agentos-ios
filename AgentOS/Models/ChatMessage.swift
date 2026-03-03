import Foundation
import GRDB

struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: String
    let conversationId: String
    let role: MessageRole
    var content: String
    let timestamp: Int
    var skillName: String?
    var attachments: [Attachment]?

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
        attachments: [Attachment]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.skillName = skillName
        self.attachments = attachments
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
    }

    init(row: Row) throws {
        id = row[CodingKeys.id]
        conversationId = row[CodingKeys.conversationId]
        role = MessageRole(rawValue: row[CodingKeys.role]) ?? .assistant
        content = row[CodingKeys.content]
        timestamp = row[CodingKeys.timestamp]
        skillName = row[CodingKeys.skillName]

        if let jsonString: String = row[CodingKeys.attachments],
           let data = jsonString.data(using: .utf8) {
            attachments = try? JSONDecoder().decode([Attachment].self, from: data)
        } else {
            attachments = nil
        }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[CodingKeys.id] = id
        container[CodingKeys.conversationId] = conversationId
        container[CodingKeys.role] = role.rawValue
        container[CodingKeys.content] = content
        container[CodingKeys.timestamp] = timestamp
        container[CodingKeys.skillName] = skillName

        if let attachments = attachments {
            let data = try JSONEncoder().encode(attachments)
            container[CodingKeys.attachments] = String(data: data, encoding: .utf8)
        } else {
            container[CodingKeys.attachments] = nil as String?
        }
    }
}
