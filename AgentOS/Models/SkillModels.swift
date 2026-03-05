import Foundation

struct SkillManifestInfo: Codable, Sendable, Identifiable, Equatable {
    let name: String
    let version: String
    let description: String
    let author: String
    let audit: String
    var auditSource: String?
    var enabled: Bool
    var installed: Bool?
    var environments: [String]?
    var category: String?
    var visibility: String?
    var emoji: String?
    var eligible: Bool?
    var source: String?
    var functions: [SkillFunction]
    var locales: [String: SkillLocale]?

    var id: String { name }

    static func == (lhs: SkillManifestInfo, rhs: SkillManifestInfo) -> Bool {
        lhs.name == rhs.name && lhs.version == rhs.version && lhs.enabled == rhs.enabled && lhs.installed == rhs.installed
    }

    func localizedName(language: String) -> String {
        locales?[language]?.displayName ?? name
    }

    func localizedDescription(language: String) -> String {
        locales?[language]?.description ?? description
    }
}

struct SkillLibraryItem: Codable, Sendable, Identifiable, Equatable {
    let name: String
    let version: String
    let description: String
    let author: String
    let category: String
    var emoji: String?
    let environments: [String]
    let permissions: [String]
    let audit: String
    var auditSource: String?
    let visibility: String
    var installed: Bool
    let isDefault: Bool
    let installCount: Int
    var featured: Bool
    var functions: [SkillFunction]
    var locales: [String: SkillLocale]?
    var skillType: String?
    var compatibleAgents: [String]?
    var installedAgents: [String: Bool]?

    var id: String { name }

    static func == (lhs: SkillLibraryItem, rhs: SkillLibraryItem) -> Bool {
        lhs.name == rhs.name && lhs.version == rhs.version && lhs.installed == rhs.installed
    }

    func localizedName(language: String) -> String {
        locales?[language]?.displayName ?? name
    }

    func localizedDescription(language: String) -> String {
        locales?[language]?.description ?? description
    }
}

struct SkillLocale: Codable, Sendable, Equatable {
    var displayName: String?
    var description: String?
    var functions: [String: String]?
}
