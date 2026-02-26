import Foundation

struct SkillCategory: Identifiable, Sendable {
    let key: String
    let label: String
    let emoji: String
    var id: String { key }
}

let skillCategories: [SkillCategory] = [
    SkillCategory(key: "all", label: "All", emoji: ""),
    SkillCategory(key: "tools", label: "Tools", emoji: ""),
    SkillCategory(key: "knowledge", label: "Knowledge", emoji: ""),
    SkillCategory(key: "productivity", label: "Productivity", emoji: ""),
    SkillCategory(key: "finance", label: "Finance", emoji: ""),
    SkillCategory(key: "creative", label: "Creative", emoji: ""),
]

@MainActor
@Observable
final class SkillsViewModel {
    var installedSkills: [SkillManifestInfo] = []
    var librarySkills: [SkillLibraryItem] = []
    var selectedCategory = "all"
    var searchQuery = ""
    var isLoading = false
    var isLibraryLoading = false
    var errorMessage = ""
    var activeTab: SkillsTab = .installed
    var selectedLibrarySkill: SkillLibraryItem?
    var addSkillMode: AddSkillMode?

    // Skill config
    var configFields: [SkillConfigField] = []
    var configValues: [String: AnyCodable] = [:]
    var configDraft: [String: String] = [:]
    var isConfigSaved = false

    enum SkillsTab: String, CaseIterable {
        case installed = "Installed"
        case library = "Library"
    }

    enum AddSkillMode: String, Identifiable {
        case http
        case mcp
        case skillmd
        case generate
        var id: String { rawValue }
    }

    private weak var wsService: WebSocketService?

    func setup(wsService: WebSocketService) {
        self.wsService = wsService
        wsService.onMessage { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
    }

    private func handleMessage(_ message: WSMessage) {
        switch message.type {
        case .skillListResponse:
            if let payload = message.payload?.dictValue,
               let skillsArray = payload["skills"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                if let data = try? JSONSerialization.data(withJSONObject: skillsArray),
                   let skills = try? decoder.decode([SkillManifestInfo].self, from: data) {
                    installedSkills = skills
                }
            }
            isLoading = false

        case .skillLibraryResponse:
            if let payload = message.payload?.dictValue,
               let libraryArray = payload["skills"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                if let data = try? JSONSerialization.data(withJSONObject: libraryArray),
                   let items = try? decoder.decode([SkillLibraryItem].self, from: data) {
                    librarySkills = items
                }
            }
            isLibraryLoading = false

        case .skillConfigResponse:
            if let payload = message.payload?.dictValue,
               let fieldsArray = payload["fields"] as? [[String: Any]],
               let configDict = payload["config"] as? [String: Any] {
                let decoder = JSONDecoder()
                if let data = try? JSONSerialization.data(withJSONObject: fieldsArray),
                   let fields = try? decoder.decode([SkillConfigField].self, from: data) {
                    configFields = fields
                }
                configValues = configDict.mapValues { AnyCodable($0) }
                configDraft = configDict.compactMapValues { $0 as? String }
            }

        default:
            break
        }
    }

    func requestSkillList() {
        guard let ws = wsService, ws.isConnected else { return }
        isLoading = true
        let msg = WSMessage(type: .skillListRequest)
        ws.send(msg)
    }

    func requestLibrary() {
        guard let ws = wsService, ws.isConnected else { return }
        isLibraryLoading = true
        let msg = WSMessage(type: .skillLibraryRequest)
        ws.send(msg)
    }

    func toggleSkill(name: String, enabled: Bool) {
        guard let ws = wsService, ws.isConnected else { return }
        let payload = SkillTogglePayload(skillName: name, enabled: enabled)
        let dict = encodeToDictionary(payload)
        let msg = WSMessage(type: .skillToggle, payload: AnyCodable(dict))
        ws.send(msg)

        // Optimistic update
        if let idx = installedSkills.firstIndex(where: { $0.name == name }) {
            installedSkills[idx].enabled = enabled
        }
    }

    func installSkill(name: String) {
        guard let ws = wsService, ws.isConnected else { return }
        let payload = SkillInstallPayload(skillName: name)
        let dict = encodeToDictionary(payload)
        let msg = WSMessage(type: .skillInstall, payload: AnyCodable(dict))
        ws.send(msg)

        // Optimistic update
        if let idx = librarySkills.firstIndex(where: { $0.name == name }) {
            librarySkills[idx].installed = true
        }

        // Refresh lists after a delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            requestSkillList()
            requestLibrary()
        }
    }

    func uninstallSkill(name: String) {
        guard let ws = wsService, ws.isConnected else { return }
        let payload: [String: Any] = ["skillName": name]
        let msg = WSMessage(type: .skillUninstall, payload: AnyCodable(payload))
        ws.send(msg)

        installedSkills.removeAll { $0.name == name }
        if let idx = librarySkills.firstIndex(where: { $0.name == name }) {
            librarySkills[idx].installed = false
        }
    }

    func requestConfig(skillName: String) {
        guard let ws = wsService, ws.isConnected else { return }
        let payload = SkillConfigGetPayload(skillName: skillName)
        let dict = encodeToDictionary(payload)
        let msg = WSMessage(type: .skillConfigGet, payload: AnyCodable(dict))
        ws.send(msg)
    }

    func saveConfig(skillName: String) {
        guard let ws = wsService, ws.isConnected else { return }
        let configAnyCodable = configDraft.mapValues { AnyCodable($0) }
        let payload = SkillConfigSetPayload(skillName: skillName, config: configAnyCodable)
        let dict = encodeToDictionary(payload)
        let msg = WSMessage(type: .skillConfigSet, payload: AnyCodable(dict))
        ws.send(msg)
        configValues = configAnyCodable
        isConfigSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isConfigSaved = false
        }
    }

    // MARK: - Filtered data

    var filteredInstalledSkills: [SkillManifestInfo] {
        var result = installedSkills
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        return result
    }

    var filteredLibrarySkills: [SkillLibraryItem] {
        var result = librarySkills
        if selectedCategory != "all" {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        return result
    }

    var featuredSkills: [SkillLibraryItem] {
        librarySkills.filter { $0.featured }
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
