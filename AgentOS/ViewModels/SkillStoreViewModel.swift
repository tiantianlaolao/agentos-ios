import Foundation

struct FeaturedSkill: Codable, Identifiable, Sendable {
    let name: String
    let description: String
    let category: String
    var emoji: String?
    let installCount: Int
    let audit: String
    var locales: [String: SkillLocale]?

    var id: String { name }

    func localizedName(language: String) -> String {
        locales?[language]?.displayName ?? name
    }

    func localizedDescription(language: String) -> String {
        locales?[language]?.description ?? description
    }
}

struct CategoryInfo: Codable, Sendable {
    let name: String
    let count: Int
}

struct SkillStoreStats: Codable, Sendable {
    let totalSkills: Int
    let mcpAvailable: Int?
    let categories: [CategoryInfo]
}

struct FeaturedResponse: Codable, Sendable {
    let featured: [FeaturedSkill]
}

struct LibraryResponse: Codable, Sendable {
    let skills: [SkillLibraryItem]
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

    private(set) var serverBaseURL: String = ""
    private(set) var authToken: String = ""

    func setup(serverUrl: String, authToken: String) {
        self.serverBaseURL = serverUrl
        self.authToken = authToken
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
            let response = try JSONDecoder().decode(FeaturedResponse.self, from: data)
            featured = response.featured
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
            categories = decoded.categories.map(\.name)
        } catch {
            print("[SkillStore] Failed to fetch stats: \(error)")
        }
    }

    func fetchLibrary() async {
        guard !serverBaseURL.isEmpty, let url = URL(string: "\(serverBaseURL)/api/skill-library") else { return }
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(for: authorizedRequest(url: url))
            let response = try JSONDecoder().decode(LibraryResponse.self, from: data)
            allSkills = response.skills
        } catch {
            print("[SkillStore] Failed to fetch library: \(error)")
        }
        isLoading = false
    }

    func installSkill(name: String, agentType: String? = nil) {
        let resolvedAgent = agentType ?? "builtin"
        print("[SkillStore] installSkill: name=\(name), agentType=\(resolvedAgent)")

        // Optimistic update
        if let idx = allSkills.firstIndex(where: { $0.name == name }) {
            allSkills[idx].installed = true
            var agents = allSkills[idx].installedAgents ?? [:]
            agents[resolvedAgent] = true
            allSkills[idx].installedAgents = agents
        }

        Task {
            guard let url = URL(string: "\(serverBaseURL)/api/skill-library/install") else { return }
            var request = authorizedRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = ["skillName": name, "agentType": resolvedAgent]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? ""
                    print("[SkillStore] Install failed: HTTP \(httpResponse.statusCode) - \(errorBody)")
                } else {
                    print("[SkillStore] Install succeeded: \(name) for \(resolvedAgent)")
                }
            } catch {
                print("[SkillStore] Install error: \(error)")
            }
        }
    }

    func uninstallSkill(name: String, agentType: String? = "builtin") {
        let resolvedAgent = agentType ?? "builtin"
        if let idx = allSkills.firstIndex(where: { $0.name == name }) {
            var agents = allSkills[idx].installedAgents ?? [:]
            agents.removeValue(forKey: resolvedAgent)
            allSkills[idx].installedAgents = agents
            // Only mark as uninstalled if no agents remain
            let stillInstalled = agents.values.contains(true)
            allSkills[idx].installed = stillInstalled
        }

        Task {
            guard let url = URL(string: "\(serverBaseURL)/api/skill-library/uninstall") else { return }
            var request = authorizedRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: String] = ["skillName": name, "agentType": resolvedAgent]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
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
