// ChangelogService — fetch in-app changelog on launch / foreground, expose
// state to SwiftUI. Posts ack on user action.
//
// API contract: server/src/changelog/schema.ts (mirror of ChangelogQueryResponse).
import Foundation

struct ChangelogItemPayload: Decodable {
    let title: String
    let detail: String?
}

// changelog.zh / .en may be plain string or { title, detail? }; decode both.
enum ChangelogItem: Decodable {
    case plain(String)
    case rich(title: String, detail: String?)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .plain(s)
        } else {
            let obj = try container.decode(ChangelogItemPayload.self)
            self = .rich(title: obj.title, detail: obj.detail)
        }
    }

    var title: String {
        switch self {
        case .plain(let s): return s
        case .rich(let title, _): return title
        }
    }
    var detail: String? {
        if case .rich(_, let d) = self { return d }
        return nil
    }
}

struct ChangelogPlatformPayload: Decodable {
    let app_store_id: String?
}

struct ChangelogPlatformsBlock: Decodable {
    let ios: ChangelogPlatformPayload?
}

struct ChangelogEntry: Decodable, Identifiable {
    let version: String
    let released_at: String
    let level: String
    let force_update: Bool
    let target_platforms: [String]
    let changelog: ChangelogContent
    let lingxi_message: ChangelogMessage?
    let platforms: ChangelogPlatformsBlock?

    /// Use version as Identifiable id (unique per file).
    var id: String { version }
}

struct ChangelogContent: Decodable {
    let zh: [ChangelogItem]
    let en: [ChangelogItem]
}

struct ChangelogMessage: Decodable {
    let zh: String
    let en: String
}

struct UserAckState: Decodable {
    let pre_version: String?
    let post_version: String?
}

struct ChangelogResponse: Decodable {
    let versions: [ChangelogEntry]
    let latest_version: String?
    let user_last_seen: UserAckState?
    let should_show_pre: Bool
    let should_show_post: Bool
}

enum ChangelogAckMode: String {
    case pre, post
}

enum ChangelogAckAction: String {
    case dismissed, clicked_detail, triggered_update
}

@MainActor
@Observable
final class ChangelogService {
    static let shared = ChangelogService()

    /// Latest fetch result. Nil if never fetched or failed.
    private(set) var response: ChangelogResponse?

    /// Latest entry (for header display).
    var latestVersion: ChangelogEntry? {
        response?.versions.first
    }

    /// Show this version in pre-mode dialog (current client < latest).
    var pendingPre: ChangelogEntry? {
        guard let r = response, r.should_show_pre, let v = r.versions.first else { return nil }
        return v
    }

    /// Show this version in post-mode dialog (just upgraded, hasn't seen new-feature intro).
    var pendingPost: ChangelogEntry? {
        guard let r = response, r.should_show_post, let v = r.versions.first else { return nil }
        return v
    }

    /// Whether there's any unacknowledged content (used for settings page red dot).
    var hasUnseenChangelog: Bool {
        pendingPre != nil || pendingPost != nil
    }

    private let platform = "ios"
    private var lastFetchAt: Date?

    /// Current installed bundle version (e.g. "3.0.1").
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fetch on app launch + foreground. Throttled to once per 5min unless force=true.
    func refresh(force: Bool = false) async {
        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < 300 {
            return
        }
        let token = (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? ""

        let baseURL = ServerConfig.shared.httpBaseURL
        var components = URLComponents(string: baseURL + "/api/changelog")
        components?.queryItems = [
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "since", value: currentVersion),
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let parsed = try JSONDecoder().decode(ChangelogResponse.self, from: data)
            self.response = parsed
            self.lastFetchAt = Date()
            print("[Changelog] fetched: latest=\(parsed.latest_version ?? "nil"), pre=\(parsed.should_show_pre), post=\(parsed.should_show_post)")
        } catch {
            print("[Changelog] fetch error: \(error)")
        }
    }

    /// Persist ack to server. Returns silently on network error — UI already dismissed.
    func ack(version: String, mode: ChangelogAckMode, action: ChangelogAckAction) async {
        let token = (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? ""
        // Without auth, server rejects /ack with 401 — skip silently.
        guard !token.isEmpty else { return }

        let baseURL = ServerConfig.shared.httpBaseURL
        guard let url = URL(string: baseURL + "/api/changelog/ack") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6

        let body: [String: Any] = [
            "version": version,
            "platform": platform,
            "mode": mode.rawValue,
            "action": action.rawValue,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse {
                print("[Changelog] ack \(mode.rawValue) \(version) action=\(action.rawValue) status=\(http.statusCode)")
            }
            // Locally clear pending state so dialog doesn't reappear.
            await refresh(force: true)
        } catch {
            print("[Changelog] ack error: \(error)")
        }
    }

    /// Open the App Store page for AgentOS. Falls back to apps.apple.com URL if itms scheme fails.
    func openAppStore(appStoreId: String?) {
        let id = appStoreId ?? "6759725374"
        let candidates = [
            "itms-apps://itunes.apple.com/app/id\(id)",
            "https://apps.apple.com/app/id\(id)",
        ]
        for s in candidates {
            if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }

    /// Open the public changelog page in default browser.
    func openChangelogPage() {
        let lang = Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
        let url = URL(string: "https://www.tybbtech.com/\(lang)/changelog")!
        UIApplication.shared.open(url)
    }
}

// UIKit import for UIApplication.shared
#if canImport(UIKit)
import UIKit
#endif
