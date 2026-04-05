import Foundation

/// Shared server config — all code reads from here (thread-safe)
final class ServerConfig: Sendable {
    static let shared = ServerConfig()
    nonisolated(unsafe) private(set) var httpBaseURL = "https://agentos.tybbtech.com"
    nonisolated(unsafe) private(set) var wsURL = "wss://agentos.tybbtech.com/ws"

    func update(wsUrl: String) {
        self.wsURL = wsUrl
        self.httpBaseURL = ServerSelector.wsToHttp(wsUrl)
        print("[ServerConfig] updated: http=\(httpBaseURL) ws=\(wsURL)")
    }
}

/// Auto-select the fastest server node (CN relay vs HK direct)
enum ServerSelector {
    struct ServerNode {
        let name: String
        let ws: String
        let http: String
    }

    #if DEBUG
    static let servers: [ServerNode] = [
        ServerNode(name: "test", ws: "wss://agentos.tybbtech.com:3201/ws", http: "https://agentos.tybbtech.com:3201"),
    ]
    static let defaultWS = "wss://agentos.tybbtech.com:3201/ws"
    #else
    static let servers: [ServerNode] = [
        ServerNode(name: "main", ws: "wss://agentos.tybbtech.com/ws", http: "https://agentos.tybbtech.com"),
    ]
    static let defaultWS = "wss://agentos.tybbtech.com/ws"
    #endif

    /// Ping a server and return latency in ms, or nil on failure
    static func ping(_ httpUrl: String, timeout: TimeInterval = 5) async -> Double? {
        guard let url = URL(string: "\(httpUrl)/api/health") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let _ = try await URLSession.shared.data(for: request)
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        } catch {
            return nil
        }
    }

    /// Select the fastest server, returns WS URL
    static func selectBest() async -> String {
        let results = await withTaskGroup(of: (ServerNode, Double?).self) { group in
            for server in servers {
                group.addTask {
                    let latency = await ping(server.http)
                    return (server, latency)
                }
            }
            var collected: [(ServerNode, Double?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (node, latency) in results {
            let ms = latency.map { String(format: "%.0fms", $0) } ?? "timeout"
            print("[ServerSelector] \(node.name): \(ms)")
        }

        let best = results
            .compactMap { node, latency -> (ServerNode, Double)? in
                guard let l = latency else { return nil }
                return (node, l)
            }
            .min(by: { $0.1 < $1.1 })

        if let best = best {
            print("[ServerSelector] selected: \(best.0.name) (\(String(format: "%.0fms", best.1)))")
            return best.0.ws
        }
        return defaultWS
    }

    /// Convert WS URL to HTTP URL
    static func wsToHttp(_ wsUrl: String) -> String {
        wsUrl
            .replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "/ws", with: "")
    }
}
