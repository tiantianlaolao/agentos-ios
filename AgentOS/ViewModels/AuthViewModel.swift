import Foundation

@MainActor
@Observable
final class AuthViewModel {
    // MARK: - Form State

    var phone = ""
    var password = ""
    var confirmPassword = ""
    var smsCode = ""
    var isLogin = true
    var isLoading = false
    var errorMessage = ""

    // MARK: - Auth State

    var isAuthenticated = false
    var hasCheckedAuth = false
    /// True only when user completed real login/register (not skip)
    var hasRealLogin = false
    var savedPhone = ""
    var userCreatedAt: Int64?
    var isLoggedIn: Bool { hasRealLogin }

    // Membership plan (S1-S6)
    var plan: String = "free"  // "free" | "member"
    var planExpires: Int64?
    var isByok: Bool = false

    /// Cross-view request to switch main tab (e.g. QuotaExceeded modal → settings)
    /// MainTabView observes this and clears it after applying.
    var requestedTab: Int?

    /// Number of days since registration (day 1 = registration day)
    var companionDays: Int? {
        guard let createdAt = userCreatedAt else { return nil }
        let ms = Int64(Date().timeIntervalSince1970 * 1000) - createdAt
        return Int(ms / 86_400_000) + 1
    }

    // MARK: - SMS Countdown

    var countdown = 0
    private var countdownTask: Task<Void, Never>?

    // MARK: - Private

    private var baseURL: String { ServerConfig.shared.httpBaseURL }

    // MARK: - Auth Actions

    func loadAuth() async {
        do {
            let token = try await DatabaseService.shared.getSetting(key: "auth_token")
            let skipped = try await DatabaseService.shared.getSetting(key: "auth_skipped")
            let loggedIn = try await DatabaseService.shared.getSetting(key: "auth_loggedIn")
            let storedPhone = try await DatabaseService.shared.getSetting(key: "auth_phone")
            let storedCreatedAt = try await DatabaseService.shared.getSetting(key: "auth_createdAt")
            let storedPlan = try await DatabaseService.shared.getSetting(key: "auth_plan")
            let storedIsByok = try await DatabaseService.shared.getSetting(key: "auth_isByok")
            let storedPlanExpires = try await DatabaseService.shared.getSetting(key: "auth_planExpires")
            isAuthenticated = (token != nil && !(token ?? "").isEmpty) || skipped == "true"
            hasRealLogin = loggedIn == "true"
            savedPhone = storedPhone ?? ""
            userCreatedAt = storedCreatedAt.flatMap { Int64($0) }
            plan = storedPlan ?? "free"
            isByok = storedIsByok == "1"
            planExpires = storedPlanExpires.flatMap { Int64($0) }
        } catch {
            isAuthenticated = false
        }
        hasCheckedAuth = true
    }

    func setPlan(plan: String, planExpires: Int64?, isByok: Bool) {
        self.plan = plan
        self.planExpires = planExpires
        self.isByok = isByok
        Task {
            try? await DatabaseService.shared.setSetting(key: "auth_plan", value: plan)
            try? await DatabaseService.shared.setSetting(key: "auth_isByok", value: isByok ? "1" : "0")
            try? await DatabaseService.shared.setSetting(key: "auth_planExpires", value: planExpires.map { String($0) } ?? "")
        }
    }

    func login() async {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        guard validatePhone(trimmedPhone) else { return }
        guard !password.isEmpty else {
            errorMessage = "Please enter password"
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            let body: [String: String] = ["phone": trimmedPhone, "password": password]
            let result = try await postJSON(endpoint: "/auth/login", body: body)

            if let ok = result["ok"] as? Bool, ok,
               let data = result["data"] as? [String: Any],
               let token = data["token"] as? String,
               let userId = data["userId"] as? String {
                let createdAt = data["createdAt"] as? Int64 ?? (data["createdAt"] as? Double).map { Int64($0) }
                let planStr = data["plan"] as? String ?? "free"
                let isByokVal = data["isByok"] as? Bool ?? false
                let planExpiresVal = data["planExpires"] as? Int64 ?? (data["planExpires"] as? Double).map { Int64($0) }
                try await saveAuth(userId: userId, phone: trimmedPhone, token: token, createdAt: createdAt, plan: planStr, isByok: isByokVal, planExpires: planExpiresVal)
                hasRealLogin = true
                savedPhone = trimmedPhone
                userCreatedAt = createdAt
                plan = planStr
                isByok = isByokVal
                planExpires = planExpiresVal
                isAuthenticated = true
                APNsService.shared.requestPermissionAndRegister()
            } else {
                let error = result["error"] as? String ?? result["message"] as? String ?? "Login failed"
                errorMessage = error
            }
        } catch {
            errorMessage = "Network error"
        }

        isLoading = false
    }

    func register() async {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        guard validatePhone(trimmedPhone) else { return }
        guard !password.isEmpty else {
            errorMessage = "Please enter password"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        guard !smsCode.isEmpty else {
            errorMessage = "Please enter verification code"
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            let body: [String: String] = [
                "phone": trimmedPhone,
                "password": password,
                "code": smsCode,
            ]
            let result = try await postJSON(endpoint: "/auth/register", body: body)

            if let ok = result["ok"] as? Bool, ok,
               let data = result["data"] as? [String: Any],
               let token = data["token"] as? String,
               let userId = data["userId"] as? String {
                let createdAt = data["createdAt"] as? Int64 ?? (data["createdAt"] as? Double).map { Int64($0) }
                let planStr = data["plan"] as? String ?? "free"
                let isByokVal = data["isByok"] as? Bool ?? false
                let planExpiresVal = data["planExpires"] as? Int64 ?? (data["planExpires"] as? Double).map { Int64($0) }
                try await saveAuth(userId: userId, phone: trimmedPhone, token: token, createdAt: createdAt, plan: planStr, isByok: isByokVal, planExpires: planExpiresVal)
                hasRealLogin = true
                savedPhone = trimmedPhone
                userCreatedAt = createdAt
                plan = planStr
                isByok = isByokVal
                planExpires = planExpiresVal
                isAuthenticated = true
                APNsService.shared.requestPermissionAndRegister()
            } else {
                let error = result["error"] as? String ?? result["message"] as? String ?? "Registration failed"
                errorMessage = error
            }
        } catch {
            errorMessage = "Network error"
        }

        isLoading = false
    }

    func sendSmsCode() async {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        guard validatePhone(trimmedPhone) else { return }

        errorMessage = ""

        do {
            let body: [String: String] = ["phone": trimmedPhone]
            let result = try await postJSON(endpoint: "/auth/send-code", body: body)

            if let ok = result["ok"] as? Bool, ok {
                startCountdown()
            } else {
                let error = result["error"] as? String ?? "Failed to send code"
                errorMessage = error
            }
        } catch {
            errorMessage = "Network error"
        }
    }

    func skipLogin() {
        Task {
            try? await DatabaseService.shared.setSetting(key: "auth_skipped", value: "true")
            isAuthenticated = true
        }
    }

    var isDeletingAccount = false
    var deleteAccountError = ""

    func deleteAccount(password: String) async -> Bool {
        isDeletingAccount = true
        deleteAccountError = ""

        do {
            let token = try await DatabaseService.shared.getSetting(key: "auth_token") ?? ""
            let url = URL(string: baseURL + "/auth/delete-account")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                deleteAccountError = "Server error"
                isDeletingAccount = false
                return false
            }

            if let ok = json["ok"] as? Bool, ok {
                await logout()
                isDeletingAccount = false
                return true
            } else {
                deleteAccountError = json["error"] as? String ?? "Delete failed"
                isDeletingAccount = false
                return false
            }
        } catch {
            deleteAccountError = "Network error"
            isDeletingAccount = false
            return false
        }
    }

    func logout() async {
        APNsService.shared.unregisterToken()
        do {
            try await DatabaseService.shared.setSetting(key: "auth_token", value: "")
            try await DatabaseService.shared.setSetting(key: "auth_userId", value: "")
            try await DatabaseService.shared.setSetting(key: "auth_phone", value: "")
            try await DatabaseService.shared.setSetting(key: "auth_loggedIn", value: "false")
            try await DatabaseService.shared.setSetting(key: "auth_skipped", value: "false")
        } catch {
            // Ignore cleanup errors
        }
        isAuthenticated = false
        hasRealLogin = false
        savedPhone = ""
        userCreatedAt = nil
        plan = "free"
        planExpires = nil
        isByok = false
        try? await DatabaseService.shared.setSetting(key: "auth_plan", value: "free")
        try? await DatabaseService.shared.setSetting(key: "auth_isByok", value: "0")
        try? await DatabaseService.shared.setSetting(key: "auth_planExpires", value: "")
        resetForm()
    }

    // MARK: - Private Helpers

    private func validatePhone(_ phone: String) -> Bool {
        guard !phone.isEmpty else {
            errorMessage = "Please enter phone number"
            return false
        }
        let phoneRegex = /^1\d{10}$/
        guard phone.wholeMatch(of: phoneRegex) != nil else {
            errorMessage = "Invalid phone number"
            return false
        }
        return true
    }

    private func saveAuth(
        userId: String,
        phone: String,
        token: String,
        createdAt: Int64? = nil,
        plan: String = "free",
        isByok: Bool = false,
        planExpires: Int64? = nil
    ) async throws {
        try await DatabaseService.shared.setSetting(key: "auth_userId", value: userId)
        try await DatabaseService.shared.setSetting(key: "auth_phone", value: phone)
        try await DatabaseService.shared.setSetting(key: "auth_token", value: token)
        try await DatabaseService.shared.setSetting(key: "auth_loggedIn", value: "true")
        try await DatabaseService.shared.setSetting(key: "auth_skipped", value: "false")
        try await DatabaseService.shared.setSetting(key: "auth_plan", value: plan)
        try await DatabaseService.shared.setSetting(key: "auth_isByok", value: isByok ? "1" : "0")
        try await DatabaseService.shared.setSetting(key: "auth_planExpires", value: planExpires.map { String($0) } ?? "")
        if let createdAt {
            try await DatabaseService.shared.setSetting(key: "auth_createdAt", value: String(createdAt))
        }
    }

    private func resetForm() {
        phone = ""
        password = ""
        confirmPassword = ""
        smsCode = ""
        isLogin = true
        errorMessage = ""
    }

    private func startCountdown() {
        countdown = 60
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while let self, self.countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self.countdown -= 1
            }
        }
    }

    private func postJSON(endpoint: String, body: [String: String]) async throws -> [String: Any] {
        let url = URL(string: baseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }
}
