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

// MARK: - Memory

/// Server returns `{ ok: Bool, data: { content: String, updatedAt: String? } | null }`
struct MemoryResponseWrapper: Codable, Sendable {
    let ok: Bool
    let data: MemoryData?
}

struct MemoryData: Codable, Sendable {
    let content: String
    let updatedAt: String?
}

struct MemorySaveRequest: Codable, Sendable {
    let content: String
}

/// Server returns `{ ok: Bool }` for save
struct MemorySaveResponseWrapper: Codable, Sendable {
    let ok: Bool
}
