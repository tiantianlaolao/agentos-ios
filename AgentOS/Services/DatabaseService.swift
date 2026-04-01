import Foundation
import GRDB

actor DatabaseService {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue?

    private init() {}

    func initialize() throws {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let dbPath = (documentsPath as NSString).appendingPathComponent("agentos.db")

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    private func migrate() throws {
        guard let dbQueue else { return }

        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "conversations", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("created_at", .integer).notNull()
                t.column("updated_at", .integer).notNull()
                t.column("mode", .text).notNull().defaults(to: "builtin")
                t.column("user_id", .text).notNull().defaults(to: "anonymous")
            }

            try db.create(table: "messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("conversation_id", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .integer).notNull()
                t.column("skill_name", .text)
            }

            try db.create(
                index: "idx_messages_conversation",
                on: "messages",
                columns: ["conversation_id", "timestamp"],
                ifNotExists: true
            )

            try db.create(table: "settings", ifNotExists: true) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2_attachments") { db in
            try db.alter(table: "messages") { t in
                t.add(column: "attachments", .text)
            }
        }

        migrator.registerMigration("v3_vault") { db in
            try db.alter(table: "messages") { t in
                t.add(column: "is_vault", .integer).defaults(to: 0)
            }
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Conversations

    func getConversations(mode: ConnectionMode? = nil, userId: String? = nil) throws -> [Conversation] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            var query = Conversation.order(Column("updated_at").desc)
            if let mode {
                query = query.filter(Column("mode") == mode.rawValue)
            }
            if let userId {
                query = query.filter(Column("user_id") == userId)
            }
            return try query.fetchAll(db)
        }
    }

    func saveConversation(_ conv: Conversation) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            try conv.save(db)
        }
    }

    func deleteConversation(id: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            _ = try Conversation.deleteOne(db, key: id)
        }
    }

    func getOrCreateSingleConversation(mode: ConnectionMode, userId: String) throws -> Conversation {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.write { db in
            if let existing = try Conversation
                .filter(Column("mode") == mode.rawValue && Column("user_id") == userId)
                .order(Column("updated_at").desc)
                .fetchOne(db)
            {
                return existing
            }
            let conv = Conversation(mode: mode, userId: userId)
            try conv.insert(db)
            return conv
        }
    }

    // MARK: - Messages

    func getMessages(conversationId: String) throws -> [ChatMessage] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try ChatMessage
                .filter(Column("conversation_id") == conversationId)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    func getMessagesPaginated(conversationId: String, limit: Int, beforeTimestamp: Int? = nil) throws -> [ChatMessage] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            var query = ChatMessage.filter(Column("conversation_id") == conversationId)
            if let beforeTimestamp {
                query = query.filter(Column("timestamp") < beforeTimestamp)
            }
            let rows = try query.order(Column("timestamp").desc).limit(limit).fetchAll(db)
            return rows.reversed()
        }
    }

    func getMessageCount(conversationId: String) throws -> Int {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try ChatMessage.filter(Column("conversation_id") == conversationId).fetchCount(db)
        }
    }

    func saveMessage(_ msg: ChatMessage) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            try msg.save(db)
        }
    }

    func deleteMessage(id: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            _ = try ChatMessage.deleteOne(db, key: id)
        }
    }

    func clearConversationMessages(conversationId: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            _ = try ChatMessage.filter(Column("conversation_id") == conversationId).deleteAll(db)
        }
    }

    func deleteOldestMessages(conversationId: String, count: Int) throws -> [(role: String, content: String)] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.write { db in
            let messages = try ChatMessage
                .filter(Column("conversation_id") == conversationId)
                .order(Column("timestamp").asc)
                .limit(count)
                .fetchAll(db)
            let result = messages.map { (role: $0.role.rawValue, content: $0.content) }
            let ids = messages.map(\.id)
            if !ids.isEmpty {
                _ = try ChatMessage.filter(ids.contains(Column("id"))).deleteAll(db)
            }
            return result
        }
    }

    // MARK: - Vault Messages

    func getMessagesPaginatedNonVault(conversationId: String, limit: Int, beforeTimestamp: Int? = nil) throws -> [ChatMessage] {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            var query = ChatMessage
                .filter(Column("conversation_id") == conversationId)
                .filter(Column("is_vault") == 0)
            if let beforeTimestamp {
                query = query.filter(Column("timestamp") < beforeTimestamp)
            }
            let rows = try query.order(Column("timestamp").desc).limit(limit).fetchAll(db)
            return rows.reversed()
        }
    }

    func getNonVaultMessageCount(conversationId: String) throws -> Int {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try ChatMessage
                .filter(Column("conversation_id") == conversationId)
                .filter(Column("is_vault") == 0)
                .fetchCount(db)
        }
    }

    // MARK: - Settings

    func getSetting(key: String) throws -> String? {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        return try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])?["value"]
        }
    }

    func setSetting(key: String, value: String) throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: [key, value]
            )
        }
    }

    // MARK: - Error

    enum DatabaseError: Error {
        case notInitialized
    }
}
