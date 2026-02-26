import Foundation
import CryptoKit

/// Manages Ed25519 device identity for OpenClaw Gateway authentication.
/// Private key stored in Keychain; device ID = SHA-256(publicKey) hex.
final class DeviceIdentityService: Sendable {
    static let shared = DeviceIdentityService()

    private static let keychainAccount = "com.agentos.device-identity-ed25519"

    private init() {}

    // MARK: - Public API

    /// Load existing key pair from Keychain, or generate and persist a new one.
    func loadOrCreateKeyPair() throws -> Curve25519.Signing.PrivateKey {
        if let existing = loadFromKeychain() {
            return existing
        }
        let newKey = Curve25519.Signing.PrivateKey()
        try saveToKeychain(newKey)
        return newKey
    }

    /// Device ID: SHA-256 of the raw 32-byte public key, hex-encoded.
    func deviceId(for key: Curve25519.Signing.PrivateKey) -> String {
        let hash = SHA256.hash(data: key.publicKey.rawRepresentation)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Public key as base64url string (no padding).
    func publicKeyBase64Url(for key: Curve25519.Signing.PrivateKey) -> String {
        base64UrlEncode(key.publicKey.rawRepresentation)
    }

    /// Sign arbitrary data and return base64url signature.
    func sign(data: Data, with key: Curve25519.Signing.PrivateKey) throws -> String {
        let signature = try key.signature(for: data)
        return base64UrlEncode(signature)
    }

    /// Build the device auth payload string for signing (matches server protocol).
    func buildAuthPayload(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int,
        token: String?,
        nonce: String?
    ) -> String {
        let version = nonce != nil ? "v2" : "v1"
        var parts = [
            version,
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token ?? ""
        ]
        if version == "v2" {
            parts.append(nonce ?? "")
        }
        return parts.joined(separator: "|")
    }

    // MARK: - Keychain

    private func loadFromKeychain() -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private func saveToKeychain(_ key: Curve25519.Signing.PrivateKey) throws {
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainWriteFailed(status)
        }
    }

    // MARK: - Helpers

    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    enum DeviceIdentityError: Error {
        case keychainWriteFailed(OSStatus)
    }
}
