import Foundation

struct InviteReward: Decodable, Identifiable {
    let id: String
    let from_user_id: String
    let days: Int
    let reward_type: String  // "register_invitee" | "register_inviter" | "first_purchase"
    let status: String       // "confirmed" | "locked" | "revoked"
    let created_at: Int64
    let phone: String?
}

struct InviteMonthly: Decodable {
    let used: Int
    let limit: Int
    let yearMonth: String
}

struct InviteStatus: Decodable {
    let inviteCode: String?
    let inviteCodeExpires: Int64?
    let isExpired: Bool
    let canUseInviteCode: Bool
    let monthly: InviteMonthly
    let rewards: [InviteReward]
}

@MainActor
final class InviteService {
    static let shared = InviteService()
    private init() {}

    private var baseURL: String { ServerConfig.shared.httpBaseURL }

    func getStatus(token: String) async -> InviteStatus? {
        guard let url = URL(string: baseURL + "/auth/invite-status") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONDecoder().decode(InviteStatus.self, from: data)
        } catch {
            return nil
        }
    }

    /// Regenerate invite code. Returns new code on success.
    func regenerate(token: String) async -> (ok: Bool, code: String?, expires: Int64?, error: String?) {
        guard let url = URL(string: baseURL + "/auth/regenerate-invite-code") else {
            return (false, nil, nil, "bad_url")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (false, nil, nil, "parse_error")
            }
            let ok = (json["ok"] as? Bool) ?? false
            let code = json["inviteCode"] as? String
            let expires = json["inviteCodeExpires"] as? Int64
                ?? (json["inviteCodeExpires"] as? Double).map { Int64($0) }
            let error = json["error"] as? String
            return (ok, code, expires, error)
        } catch {
            return (false, nil, nil, "network_error")
        }
    }

    func apply(token: String, inviteCode: String) async -> (ok: Bool, error: String?) {
        guard let url = URL(string: baseURL + "/auth/apply-invite-code") else {
            return (false, "bad_url")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["inviteCode": inviteCode])
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (false, "parse_error")
            }
            let ok = (json["ok"] as? Bool) ?? false
            return (ok, json["error"] as? String)
        } catch {
            return (false, "network_error")
        }
    }

    func posterURL(code: String) -> URL? {
        URL(string: baseURL + "/api/invite/poster?code=\(code)")
    }

    func shareURL(code: String) -> String {
        "https://www.tybbtech.com/invite/\(code)"
    }

    /// Extract a 6-digit invite code from clipboard text (URL or bare code).
    static func extractInviteCode(from text: String) -> String? {
        let urlPattern = #"tybbtech\.com/(?:zh/|en/)?invite/([1-9]\d{5})"#
        if let r = text.range(of: urlPattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(text[r])
            if let codeRange = match.range(of: #"[1-9]\d{5}$"#, options: .regularExpression) {
                return String(match[codeRange])
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[1-9]\d{5}$"#, options: .regularExpression) != nil {
            return trimmed
        }
        return nil
    }
}
