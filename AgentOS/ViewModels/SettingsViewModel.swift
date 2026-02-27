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
    var activationError: String = ""

    // App
    var locale: String = "zh"
    var serverUrl: String = "http://43.155.104.45:3100"

    // UI
    var isSaving: Bool = false
    var showSaved: Bool = false

    private let db = DatabaseService.shared
    private var pollTask: Task<Void, Never>?
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
            if let v = try await db.getSetting(key: ukey("copawSubMode")) { copawSubMode = v }
            if let v = try await db.getSetting(key: ukey("copawUrl")) { copawUrl = v }
            if let v = try await db.getSetting(key: ukey("copawToken")) { copawToken = v }
            if let v = try await db.getSetting(key: ukey("locale")) { locale = v }
            if let v = try await db.getSetting(key: ukey("serverUrl")), !v.isEmpty { serverUrl = v }
            if let v = try await db.getSetting(key: ukey("hostedActivated")) { hostedActivated = v == "true" }
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
            try await db.setSetting(key: ukey("mode"), value: mode.rawValue)
            try await db.setSetting(key: ukey("builtinSubMode"), value: builtinSubMode)
            try await db.setSetting(key: ukey("provider"), value: provider.rawValue)
            try await db.setSetting(key: ukey("apiKey"), value: apiKey)
            try await db.setSetting(key: ukey("selectedModel"), value: selectedModel)
            try await db.setSetting(key: ukey("openclawSubMode"), value: openclawSubMode)
            try await db.setSetting(key: ukey("openclawUrl"), value: openclawUrl)
            try await db.setSetting(key: ukey("openclawToken"), value: openclawToken)
            try await db.setSetting(key: ukey("copawSubMode"), value: copawSubMode)
            try await db.setSetting(key: ukey("copawUrl"), value: copawUrl)
            try await db.setSetting(key: ukey("copawToken"), value: copawToken)
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

    // MARK: - Hosted

    func fetchHostedStatus() async {
        do {
            let token = try await db.getSetting(key: "auth_token")
            guard let token, token != "skip" else { return }

            let service = HostedAPIService(baseURL: serverUrl)
            let status = try await service.getStatus(authToken: token)
            hostedActivated = status.activated
            if let account = status.account {
                hostedQuotaUsed = account.quotaUsed
                hostedQuotaTotal = account.quotaTotal
                hostedInstanceStatus = account.instanceStatus ?? "ready"
            }

            if hostedActivated {
                try await db.setSetting(key: ukey("hostedActivated"), value: "true")
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
        activationError = ""
        do {
            let token = try await db.getSetting(key: "auth_token")
            guard let token, token != "skip" else {
                activationError = "请先登录"
                isActivating = false
                return
            }
            let service = HostedAPIService(baseURL: serverUrl)
            let result = try await service.redeemCode(invitationCode.trimmed, authToken: token)
            if result.success == true {
                hostedActivated = true
                try await db.setSetting(key: ukey("hostedActivated"), value: "true")
                invitationCode = ""
                await fetchHostedStatus()
            } else {
                activationError = result.error ?? "激活失败"
            }
        } catch {
            activationError = error.localizedDescription
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
                    if let account = status.account {
                        hostedInstanceStatus = account.instanceStatus ?? "ready"
                        hostedQuotaUsed = account.quotaUsed
                        hostedQuotaTotal = account.quotaTotal
                    }
                } catch { break }
            }
        }
    }
}
