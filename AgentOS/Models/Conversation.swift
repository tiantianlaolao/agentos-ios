import Foundation
import GRDB

struct Conversation: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    let createdAt: Int
    var updatedAt: Int
    var mode: ConnectionMode
    var userId: String

    init(
        id: String = UUID().uuidString,
        title: String = "Chat",
        createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000),
        mode: ConnectionMode = .builtin,
        userId: String = "anonymous"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mode = mode
        self.userId = userId
    }
}

// MARK: - GRDB

extension Conversation: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mode
        case userId = "user_id"
    }
}
