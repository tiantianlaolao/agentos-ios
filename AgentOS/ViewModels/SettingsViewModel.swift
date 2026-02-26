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
    var openclawSubMode: String = "hosted" // "hosted" or "selfhosted"
    var openclawUrl: String = ""
    var openclawToken: String = ""

    // CoPaw
    var copawSubMode: String = "hosted"
    var copawUrl: String = ""
    var copawToken: String = ""

    // Hosted
    var hostedActivated: Bool = false
    var hostedQuotaUsed: Int = 0
    var hostedQuotaTotal: Int = 0
    var hostedInstanceStatus: String = "pending"
    var invitationCode: String = ""
    var isActivating: Bool = false

    // App
    var locale: String = "zh"
    var serverUrl: String = "http://150.109.157.27:3100"

    // UI
    var isSaving: Bool = false
    var showSaved: Bool = false

    private let db = DatabaseService.shared
    private var pollTask: Task<Void, Never>?

    // MARK: - Load

    func loadSettings() async {
        do {
            if let v = try await db.getSetting(key: "mode") { mode = ConnectionMode(rawValue: v) ?? .builtin }
            if let v = try await db.getSetting(key: "builtinSubMode") { builtinSubMode = v }
            if let v = try await db.getSetting(key: "provider") { provider = LLMProvider(rawValue: v) ?? .deepseek }
            if let v = try await db.getSetting(key: "apiKey") { apiKey = v }
            if let v = try await db.getSetting(key: "selectedModel") { selectedModel = v.isEmpty ? "deepseek" : v }
            if let v = try await db.getSetting(key: "openclawSubMode") { openclawSubMode = v }
            if let v = try await db.getSetting(key: "openclawUrl") { openclawUrl = v }
            if let v = try await db.getSetting(key: "openclawToken") { openclawToken = v }
            if let v = try await db.getSetting(key: "copawSubMode") { copawSubMode = v }
            if let v = try await db.getSetting(key: "copawUrl") { copawUrl = v }
            if let v = try await db.getSetting(key: "copawToken") { copawToken = v }
            if let v = try await db.getSetting(key: "locale") { locale = v }
            if let v = try await db.getSetting(key: "serverUrl"), !v.isEmpty { serverUrl = v }
            if let v = try await db.getSetting(key: "hostedActivated") { hostedActivated = v == "true" }
        } catch {
            print("[Settings] Load error: \(error)")
        }

        // Fetch hosted status
        await fetchHostedStatus()
    }

    // MARK: - Save

    func saveSettings() async {
        isSaving = true
        do {
            try await db.setSetting(key: "mode", value: mode.rawValue)
            try await db.setSetting(key: "builtinSubMode", value: builtinSubMode)
            try await db.setSetting(key: "provider", value: provider.rawValue)
            try await db.setSetting(key: "apiKey", value: apiKey)
            try await db.setSetting(key: "selectedModel", value: selectedModel)
            try await db.setSetting(key: "openclawSubMode", value: openclawSubMode)
            try await db.setSetting(key: "openclawUrl", value: openclawUrl)
            try await db.setSetting(key: "openclawToken", value: openclawToken)
            try await db.setSetting(key: "copawSubMode", value: copawSubMode)
            try await db.setSetting(key: "copawUrl", value: copawUrl)
            try await db.setSetting(key: "copawToken", value: copawToken)
            try await db.setSetting(key: "locale", value: locale)
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

    // MARK: - Hosted

    func fetchHostedStatus() async {
        do {
            let token = try await db.getSetting(key: "auth_token")
            guard let token, token != "skip" else { return }

            let service = HostedAPIService(baseURL: serverUrl)
            let status = try await service.getStatus(authToken: token)
            hostedActivated = status.activated
            hostedQuotaUsed = status.quotaUsed
            hostedQuotaTotal = status.quotaTotal
            hostedInstanceStatus = status.instanceStatus ?? "ready"

            if hostedActivated {
                try await db.setSetting(key: "hostedActivated", value: "true")
            }

            // Poll if provisioning
            if hostedInstanceStatus == "provisioning" {
                startPolling(token: token)
            }
        } catch {
            // ignore
        }
    }

    func activateInvitationCode() async {
        guard !invitationCode.trimmed.isEmpty else { return }
        isActivating = true
        do {
            let token = try await db.getSetting(key: "auth_token")
            guard let token, token != "skip" else {
                isActivating = false
                return
            }
            let service = HostedAPIService(baseURL: serverUrl)
            _ = try await service.redeemCode(invitationCode.trimmed, authToken: token)
            hostedActivated = true
            try await db.setSetting(key: "hostedActivated", value: "true")
            invitationCode = ""
            await fetchHostedStatus()
        } catch {
            print("[Settings] Activation error: \(error)")
        }
        isActivating = false
    }

    private func startPolling(token: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled && hostedInstanceStatus == "provisioning" {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                do {
                    let service = HostedAPIService(baseURL: serverUrl)
                    let status = try await service.getStatus(authToken: token)
                    hostedInstanceStatus = status.instanceStatus ?? "ready"
                    hostedQuotaUsed = status.quotaUsed
                    hostedQuotaTotal = status.quotaTotal
                } catch { break }
            }
        }
    }
}
