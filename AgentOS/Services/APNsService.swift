import Foundation
import UIKit
import UserNotifications

/// Manages APNs push notification registration and device token upload.
///
/// Usage:
///   - Call `requestPermissionAndRegister()` after user logs in
///   - Call `unregisterToken()` on logout
///   - System calls `didRegisterForRemoteNotifications` via AppDelegate
final class APNsService: NSObject, @unchecked Sendable {
    static let shared = APNsService()

    /// Last uploaded token (avoid duplicate uploads)
    private var lastUploadedToken: String?
    private var cachedAuthToken: String?

    private var baseURL: String { ServerConfig.shared.httpBaseURL }

    // MARK: - Public API

    /// Request notification permission and register for remote notifications.
    /// Safe to call multiple times; iOS only prompts once.
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                print("[APNs] Permission error: \(error.localizedDescription)")
                return
            }
            print("[APNs] Permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Called by AppDelegate when iOS returns the device token.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNs] Device token: \(token.prefix(16))...")

        guard token != lastUploadedToken else {
            print("[APNs] Token already uploaded, skipping")
            return
        }

        Task {
            await uploadToken(token)
        }
    }

    /// Called by AppDelegate when registration fails.
    func didFailToRegister(error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
        // Silently degrade - push won't work but app functions normally
    }

    /// Remove device token from server (call on logout).
    func unregisterToken() {
        guard lastUploadedToken != nil else { return }
        Task {
            await deleteToken()
        }
        lastUploadedToken = nil
        cachedAuthToken = nil
    }

    // MARK: - Token Upload

    private func uploadToken(_ token: String) async {
        guard let authToken = await getAuthToken() else {
            print("[APNs] No auth token, skipping upload")
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/device-token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: String] = ["platform": "ios", "token": token]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                lastUploadedToken = token
                print("[APNs] Token uploaded successfully")
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[APNs] Upload failed: \(body)")
            }
        } catch {
            print("[APNs] Upload error: \(error.localizedDescription)")
        }
    }

    private func deleteToken() async {
        guard let authToken = await getAuthToken() else { return }
        guard let url = URL(string: "\(baseURL)/auth/device-token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let body: [String: String] = ["platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let _ = try await URLSession.shared.data(for: request)
            print("[APNs] Token deleted from server")
        } catch {
            print("[APNs] Delete error: \(error.localizedDescription)")
        }
    }

    private func getAuthToken() async -> String? {
        if let cached = cachedAuthToken, !cached.isEmpty {
            return cached
        }
        let token = try? await DatabaseService.shared.getSetting(key: "auth_token")
        cachedAuthToken = token
        return token
    }
}
