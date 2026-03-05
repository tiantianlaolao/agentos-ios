import Foundation

struct FeaturedSkill: Codable, Identifiable, Sendable {
    let name: String
    let description: String
    let category: String
    var emoji: String?
    let installCount: Int
    let audit: String

    var id: String { name }
}

struct SkillStoreStats: Codable, Sendable {
    let totalSkills: Int
    let totalInstalls: Int
    let categories: [String]
}

@MainActor
@Observable
final class SkillStoreViewModel {
    var featured: [FeaturedSkill] = []
    var allSkills: [SkillLibraryItem] = []
    var categories: [String] = []
    var searchText = ""
    var selectedCategory = "all"
    var isLoading = false
    var stats: SkillStoreStats?

    private var serverBaseURL: String = ""
    private var authToken: String = ""
    private weak var wsService: WebSocketService?

    func setup(wsService: WebSocketService, serverUrl: String? = nil, authToken: String? = nil) {
        self.wsService = wsService
        if let url = serverUrl, !url.isEmpty {
            self.serverBaseURL = url
        }
        if let token = authToken {
            self.authToken = token
        }
        wsService.onMessage { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message)
            }
        }
    }

    private func handleMessage(_ message: WSMessage) {
        if message.type == .skillLibraryResponse {
            if let payload = message.payload?.dictValue,
               let libraryArray = payload["skills"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                if let data = try? JSONSerialization.data(withJSONObject: libraryArray),
                   let items = try? decoder.decode([SkillLibraryItem].self, from: data) {
                    allSkills = items
                }
            }
            isLoading = false
        }
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func fetchFeatured() async {
        guard !serverBaseURL.isEmpty, let url = URL(string: "\(serverBaseURL)/api/skill-store/featured") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            featured = try JSONDecoder().decode([FeaturedSkill].self, from: data)
        } catch {
            print("[SkillStore] Failed to fetch featured: \(error)")
        }
    }

    func fetchStats() async {
        guard !serverBaseURL.isEmpty, let url = URL(string: "\(serverBaseURL)/api/skill-store/stats") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let decoded = try JSONDecoder().decode(SkillStoreStats.self, from: data)
            stats = decoded
            categories = decoded.categories
        } catch {
            print("[SkillStore] Failed to fetch stats: \(error)")
        }
    }

    func fetchLibrary() {
        guard let ws = wsService, ws.isConnected else { return }
        isLoading = true
        let msg = WSMessage(type: .skillLibraryRequest)
        ws.send(msg)
    }

    func installSkill(name: String, agentType: String? = nil) {
        guard let ws = wsService, ws.isConnected else { return }
        var payload: [String: Any] = ["skillName": name]
        if let agentType { payload["agentType"] = agentType }
        let msg = WSMessage(type: .skillInstall, payload: AnyCodable(payload))
        ws.send(msg)

        // Optimistic update
        if let idx = allSkills.firstIndex(where: { $0.name == name }) {
            allSkills[idx].installed = true
            if let agentType {
                var agents = allSkills[idx].installedAgents ?? [:]
                agents[agentType] = true
                allSkills[idx].installedAgents = agents
            }
        }
    }

    func uninstallSkill(name: String, agentType: String? = nil) {
        guard let ws = wsService, ws.isConnected else { return }
        var payload: [String: Any] = ["skillName": name]
        if let agentType { payload["agentType"] = agentType }
        let msg = WSMessage(type: .skillUninstall, payload: AnyCodable(payload))
        ws.send(msg)

        if let idx = allSkills.firstIndex(where: { $0.name == name }) {
            allSkills[idx].installed = false
        }
    }

    var filteredSkills: [SkillLibraryItem] {
        var result = allSkills
        if selectedCategory != "all" {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        return result
    }
}
