import Foundation
import Observation

struct CoderLinkRequest: Identifiable, Equatable {
    let id = UUID()
    let action: CoderAction

    static func parse(_ url: URL) -> CoderLinkRequest? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "coder.tybbtech.com",
              parts.port == nil || parts.port == 443,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == "/app/open" else { return nil }
        let query = parts.queryItems ?? []
        guard query.allSatisfy({ ["action", "remix"].contains($0.name) }),
              query.filter({ $0.name == "action" }).count == 1 else { return nil }
        let kind = query.first(where: { $0.name == "action" })?.value
        let remixes = query.filter { $0.name == "remix" }
        if kind == "new", remixes.isEmpty { return CoderLinkRequest(action: CoderAction(startNew: true)) }
        guard kind == "remix", remixes.count == 1, let id = remixes.first?.value,
              !id.isEmpty, id.utf8.count <= 80,
              id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return CoderLinkRequest(action: CoderAction(remix: id))
    }
}

/// Retain a public action through login; never store an account token in a link.
@Observable @MainActor
final class CoderLinkRouter {
    static let shared = CoderLinkRouter()
    var pending: CoderLinkRequest?
    var presented: CoderLinkRequest?
    var authenticated = false
    private var active = Set<UUID>()

    func receive(_ url: URL) {
        guard let request = CoderLinkRequest.parse(url) else { return }
        pending = request
        presentPending()
    }
    func entered(_ id: UUID) { active.insert(id) }
    func left(_ id: UUID) { active.remove(id) }
    func presentPending() {
        guard authenticated, active.isEmpty, presented == nil, let request = pending else { return }
        pending = nil
        presented = request
    }
    func takePending(_ id: UUID) -> CoderAction? {
        guard let request = pending, request.id == id else { return nil }
        pending = nil
        return request.action
    }
}
