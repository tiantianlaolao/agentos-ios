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
    var isLoggedIn: Bool { hasRealLogin }

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
            isAuthenticated = (token != nil && !(token ?? "").isEmpty) || skipped == "true"
            hasRealLogin = loggedIn == "true"
            savedPhone = storedPhone ?? ""
        } catch {
            isAuthenticated = false
        }
        hasCheckedAuth = true
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
                try await saveAuth(userId: userId, phone: trimmedPhone, token: token)
                hasRealLogin = true
                savedPhone = trimmedPhone
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
                try await saveAuth(userId: userId, phone: trimmedPhone, token: token)
                hasRealLogin = true
                savedPhone = trimmedPhone
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

    private func saveAuth(userId: String, phone: String, token: String) async throws {
        try await DatabaseService.shared.setSetting(key: "auth_userId", value: userId)
        try await DatabaseService.shared.setSetting(key: "auth_phone", value: phone)
        try await DatabaseService.shared.setSetting(key: "auth_token", value: token)
        try await DatabaseService.shared.setSetting(key: "auth_loggedIn", value: "true")
        try await DatabaseService.shared.setSetting(key: "auth_skipped", value: "false")
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
