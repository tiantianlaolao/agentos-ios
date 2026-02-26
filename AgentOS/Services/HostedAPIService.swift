import Foundation

/// REST API client for AgentOS hosted mode endpoints.
final class HostedAPIService: Sendable {
    static let shared = HostedAPIService()

    private let baseURL: String

    init(baseURL: String = "http://43.154.188.177:3100") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// GET /hosted/status — check hosted activation status.
    func getStatus(authToken: String) async throws -> HostedStatusResponse {
        guard let url = URL(string: "\(baseURL)/hosted/status") else {
            throw HostedAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw HostedAPIError.requestFailed
        }
        return try JSONDecoder().decode(HostedStatusResponse.self, from: data)
    }

    /// POST /hosted/redeem — redeem an invitation code.
    func redeemCode(_ code: String, authToken: String) async throws -> RedeemCodeResponse {
        guard let url = URL(string: "\(baseURL)/hosted/redeem") else {
            throw HostedAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = RedeemCodeRequest(code: code)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw HostedAPIError.requestFailed
        }
        return try JSONDecoder().decode(RedeemCodeResponse.self, from: data)
    }

    enum HostedAPIError: Error, LocalizedError {
        case invalidURL
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid hosted API URL"
            case .requestFailed: return "Hosted API request failed"
            }
        }
    }
}
