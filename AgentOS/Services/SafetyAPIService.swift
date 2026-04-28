import Foundation

/// REST API client for safety/compliance endpoints (P1-C complaint + R4 personalization).
final class SafetyAPIService: Sendable {
    static let shared = SafetyAPIService()

    private let baseURL: String

    init(baseURL: String = ServerConfig.shared.httpBaseURL) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Complaint

    struct ComplaintBody: Encodable {
        let description: String
        let reporter_email: String?
    }

    struct ComplaintResponse: Decodable {
        let ok: Bool
        let complaint_id: Int?
        let ts: Int?
        let message: String?
        let error: String?
    }

    /// POST /api/safety/complaint — submit a complaint (JWT required).
    func submitComplaint(description: String, email: String?, authToken: String) async throws -> ComplaintResponse {
        guard let url = URL(string: "\(baseURL)/api/safety/complaint") else {
            throw SafetyAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body = ComplaintBody(
            description: description,
            reporter_email: (email?.isEmpty ?? true) ? nil : email
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ComplaintResponse.self, from: data)
    }

    // MARK: - Personalization toggle (R4)

    struct PersonalizationResponse: Decodable {
        let ok: Bool
        let enabled: Bool?
        let error: String?
    }

    struct PersonalizationBody: Encodable {
        let enabled: Bool
    }

    /// GET /api/user/settings/personalization
    func getPersonalization(authToken: String) async throws -> PersonalizationResponse {
        guard let url = URL(string: "\(baseURL)/api/user/settings/personalization") else {
            throw SafetyAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PersonalizationResponse.self, from: data)
    }

    /// PUT /api/user/settings/personalization
    func setPersonalization(enabled: Bool, authToken: String) async throws -> PersonalizationResponse {
        guard let url = URL(string: "\(baseURL)/api/user/settings/personalization") else {
            throw SafetyAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(PersonalizationBody(enabled: enabled))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PersonalizationResponse.self, from: data)
    }

    enum SafetyAPIError: Error, LocalizedError {
        case invalidURL
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid safety API URL"
            }
        }
    }
}
