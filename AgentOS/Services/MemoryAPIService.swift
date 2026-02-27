import Foundation

/// REST API client for AgentOS user memory endpoints.
final class MemoryAPIService: Sendable {
    static let shared = MemoryAPIService()

    private let baseURL: String

    init(baseURL: String = "http://43.155.104.45:3100") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// GET /memory — retrieve user memory content.
    /// Server returns `{ ok: true, data: { content, updatedAt } | null }`.
    func getMemory(authToken: String) async throws -> MemoryData? {
        guard let url = URL(string: "\(baseURL)/memory") else {
            throw MemoryAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MemoryAPIError.requestFailed
        }
        let wrapper = try JSONDecoder().decode(MemoryResponseWrapper.self, from: data)
        guard wrapper.ok else { throw MemoryAPIError.requestFailed }
        return wrapper.data
    }

    /// POST /memory — save user memory content.
    /// Server returns `{ ok: true }`.
    func saveMemory(content: String, authToken: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/memory") else {
            throw MemoryAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = MemorySaveRequest(content: content)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MemoryAPIError.requestFailed
        }
        let wrapper = try JSONDecoder().decode(MemorySaveResponseWrapper.self, from: data)
        return wrapper.ok
    }

    enum MemoryAPIError: Error, LocalizedError {
        case invalidURL
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid memory API URL"
            case .requestFailed: return "Memory API request failed"
            }
        }
    }
}
