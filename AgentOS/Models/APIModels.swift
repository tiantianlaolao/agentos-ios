import Foundation

// MARK: - Auth

struct AuthResponse: Codable, Sendable {
    let token: String
    let userId: String
}

struct LoginRequest: Codable, Sendable {
    let phone: String
    let password: String
}

struct RegisterRequest: Codable, Sendable {
    let phone: String
    let password: String
    let confirmPassword: String
    let smsCode: String
}

struct SendCodeRequest: Codable, Sendable {
    let phone: String
}

struct SendCodeResponse: Codable, Sendable {
    let success: Bool
    var message: String?
}

struct ErrorResponse: Codable, Sendable {
    let error: String
}

// MARK: - Hosted

struct HostedStatusResponse: Codable, Sendable {
    let activated: Bool
    let quotaUsed: Int
    let quotaTotal: Int
    var instanceStatus: String?
}

struct RedeemCodeRequest: Codable, Sendable {
    let code: String
}

struct RedeemCodeResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

// MARK: - Memory

struct MemoryResponse: Codable, Sendable {
    let memory: String
    let updatedAt: String?
}

struct MemorySaveRequest: Codable, Sendable {
    let memory: String
}

struct MemorySaveResponse: Codable, Sendable {
    let success: Bool
}
