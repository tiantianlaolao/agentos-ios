import Foundation

struct UsageQuota: Decodable {
    let msg: Int
    let backtest: Int
    let search: Int
    let image_monthly: Int
    let proactive_tasks: Int
    let proactive_triggers_per_task: Int
}

struct UsageDaily: Decodable {
    let msg: Int
    let backtest: Int
    let search: Int
}

struct UsageResponse: Decodable {
    let plan: String
    let isByok: Bool
    let isExpired: Bool
    let daily: UsageDaily
    let monthlyImage: Int
    let quota: UsageQuota
}

final class UsageService: Sendable {
    static let shared = UsageService()

    func fetch(token: String) async -> UsageResponse? {
        let baseURL = ServerConfig.shared.httpBaseURL
        guard let url = URL(string: baseURL + "/api/usage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            return nil
        }
    }
}
