import Foundation

@MainActor
@Observable
final class SettingsViewModel {
    // Connection
    var mode: ConnectionMode = .builtin
    var builtinSubMode: String = "free" // "free" or "byok"
    var provider: LLMProvider = .deepseek
    var apiKey: String = ""
    var selectedModel: String = "deepseek"

    // OpenClaw
    var openclawSubMode: String = "selfhosted" // "hosted" or "selfhosted"
    var openclawUrl: String = ""
    var openclawToken: String = ""

    // Agent (unified)
    var agentSubMode: String = "direct" // "direct" | "deploy"
    var agentId: String = "openclaw" // "openclaw" | "copaw" | "custom"
    var directTarget: String = "remote" // "local" | "remote"
    var agentUrl: String = ""
    var agentToken: String = ""

    // CoPaw
    var copawSubMode: String = "deploy" // "deploy" | "selfhosted"
    var copawUrl: String = ""
    var copawToken: String = ""
    var copawDeployType: String = "local" // "cloud" | "local"
    var copawSelfhostedType: String = "remote" // "remote" | "local"
    var copawDeployModelMode: String = "default" // "default" | "custom"
    var copawDeployProvider: String = "deepseek"
    var copawDeployApiKey: String = ""
    var copawDeployModel: String = ""

    // App
    var locale: String = "zh"
    var serverUrl: String = ServerConfig.shared.httpBaseURL

    // UI
    var isSaving: Bool = false
    var showSaved: Bool = false

    private let db = DatabaseService.shared
    private var currentUserId: String = ""

    /// Build a user-specific settings key
    private func ukey(_ key: String) -> String {
        guard !currentUserId.isEmpty else { return key }
        return "\(currentUserId):\(key)"
    }

    // MARK: - Load

    func loadSettings() async {
        do {
            // Load userId first (auth keys are global)
            if let uid = try await db.getSetting(key: "auth_userId"), !uid.isEmpty {
                currentUserId = uid
            } else {
                currentUserId = ""
            }

            // Load user-specific settings
            if let v = try await db.getSetting(key: ukey("mode")) { mode = ConnectionMode(rawValue: v) ?? .builtin }
            if let v = try await db.getSetting(key: ukey("builtinSubMode")) { builtinSubMode = v }
            if let v = try await db.getSetting(key: ukey("provider")) { provider = LLMProvider(rawValue: v) ?? .deepseek }
            if let v = try await db.getSetting(key: ukey("apiKey")) { apiKey = v }
            if let v = try await db.getSetting(key: ukey("selectedModel")) { selectedModel = v.isEmpty ? "deepseek" : v }
            if let v = try await db.getSetting(key: ukey("openclawSubMode")) { openclawSubMode = v }
            if let v = try await db.getSetting(key: ukey("openclawUrl")) { openclawUrl = v }
            if let v = try await db.getSetting(key: ukey("openclawToken")) { openclawToken = v }
            if let v = try await db.getSetting(key: ukey("agentSubMode")) { agentSubMode = v }
            if let v = try await db.getSetting(key: ukey("agentId")) { agentId = v }
            if let v = try await db.getSetting(key: ukey("directTarget")) { directTarget = v }
            if let v = try await db.getSetting(key: ukey("agentUrl")) { agentUrl = v }
            if let v = try await db.getSetting(key: ukey("agentToken")) { agentToken = v }
            if let v = try await db.getSetting(key: ukey("copawSubMode")) { copawSubMode = v }
            if let v = try await db.getSetting(key: ukey("copawUrl")) { copawUrl = v }
            if let v = try await db.getSetting(key: ukey("copawToken")) { copawToken = v }
            if let v = try await db.getSetting(key: ukey("copawDeployType")) { copawDeployType = v }
            if let v = try await db.getSetting(key: ukey("copawSelfhostedType")) { copawSelfhostedType = v }
            if let v = try await db.getSetting(key: ukey("copawDeployModelMode")) { copawDeployModelMode = v }
            if let v = try await db.getSetting(key: ukey("copawDeployProvider")) { copawDeployProvider = v }
            if let v = try await db.getSetting(key: ukey("copawDeployApiKey")) { copawDeployApiKey = v }
            if let v = try await db.getSetting(key: ukey("copawDeployModel")) { copawDeployModel = v }
            if let v = try await db.getSetting(key: ukey("locale")) { locale = v }
            if let v = try await db.getSetting(key: ukey("serverUrl")), !v.isEmpty { serverUrl = v }
        } catch {
            print("[Settings] Load error: \(error)")
        }

        // Map persisted runtime mode back to .agent for UI display
        // when the mode matches the agentId (came from agent settings tab)
        if (mode == .openclaw && agentId == "openclaw") ||
           (mode == .copaw && agentId == "copaw") {
            mode = .agent
        }
    }

    // MARK: - Save

    /// Resolve .agent to the real runtime mode based on agentId.
    /// Known agents (openclaw/copaw) use their native mode for conversation isolation and skills routing.
    var resolvedMode: ConnectionMode {
        guard mode == .agent else { return mode }
        switch agentId {
        case "openclaw": return .openclaw
        case "copaw": return .copaw
        default: return .agent  // truly custom agents
        }
    }

    func saveSettings() async {
        isSaving = true
        do {
            // Save the resolved mode (not .agent for known agents)
            try await db.setSetting(key: ukey("mode"), value: resolvedMode.rawValue)
            try await db.setSetting(key: ukey("builtinSubMode"), value: builtinSubMode)
            try await db.setSetting(key: ukey("provider"), value: provider.rawValue)
            try await db.setSetting(key: ukey("apiKey"), value: apiKey)
            try await db.setSetting(key: ukey("selectedModel"), value: selectedModel)
            try await db.setSetting(key: ukey("openclawSubMode"), value: openclawSubMode)
            try await db.setSetting(key: ukey("openclawUrl"), value: openclawUrl)
            try await db.setSetting(key: ukey("openclawToken"), value: openclawToken)
            try await db.setSetting(key: ukey("agentSubMode"), value: agentSubMode)
            try await db.setSetting(key: ukey("agentId"), value: agentId)
            try await db.setSetting(key: ukey("directTarget"), value: directTarget)
            try await db.setSetting(key: ukey("agentUrl"), value: agentUrl)
            try await db.setSetting(key: ukey("agentToken"), value: agentToken)
            try await db.setSetting(key: ukey("copawSubMode"), value: copawSubMode)
            try await db.setSetting(key: ukey("copawUrl"), value: copawUrl)
            try await db.setSetting(key: ukey("copawToken"), value: copawToken)
            try await db.setSetting(key: ukey("copawDeployType"), value: copawDeployType)
            try await db.setSetting(key: ukey("copawSelfhostedType"), value: copawSelfhostedType)
            try await db.setSetting(key: ukey("copawDeployModelMode"), value: copawDeployModelMode)
            try await db.setSetting(key: ukey("copawDeployProvider"), value: copawDeployProvider)
            try await db.setSetting(key: ukey("copawDeployApiKey"), value: copawDeployApiKey)
            try await db.setSetting(key: ukey("copawDeployModel"), value: copawDeployModel)
            try await db.setSetting(key: ukey("locale"), value: locale)
        } catch {
            print("[Settings] Save error: \(error)")
        }
        isSaving = false
        showSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSaved = false
        }
    }

}
