import StoreKit

@Observable
@MainActor
class StoreService {
    static let shared = StoreService()

    private let productIds = [
        "com.agentosplus.membership.monthly",
        "com.agentosplus.membership.yearly"
    ]

    var products: [Product] = []
    var purchaseInProgress = false
    var errorMessage: String?
    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = nil
        startListening()
    }

    private func startListening() {
        updateListenerTask = listenForTransactionUpdates()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
                .sorted { $0.price < $1.price } // monthly first
        } catch {
            print("[Store] Failed to load products: \(error)")
            errorMessage = "无法加载商品信息"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        errorMessage = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Verify with our server
                let serverOk = await verifyWithServer(transaction: transaction, productId: product.id)
                if serverOk {
                    await transaction.finish()
                    return true
                } else {
                    errorMessage = "服务器验证失败，请稍后重试"
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "购买待确认（如家长审批），请稍后检查"
                return false
            @unknown default:
                return false
            }
        } catch {
            print("[Store] Purchase failed: \(error)")
            errorMessage = "购买失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            // Check current entitlements after sync
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result) {
                    let _ = await verifyWithServer(transaction: transaction, productId: transaction.productID)
                    await transaction.finish()
                }
            }
        } catch {
            print("[Store] Restore failed: \(error)")
            errorMessage = "恢复购买失败"
        }
    }

    // MARK: - Listen for Transaction Updates

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { @MainActor in
            for await result in Transaction.updates {
                if let transaction = try? checkVerified(result) {
                    let _ = await verifyWithServer(transaction: transaction, productId: transaction.productID)
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verify with Server

    private func verifyWithServer(transaction: Transaction, productId: String) async -> Bool {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else {
            print("[Store] No auth token, skipping server verify")
            return false
        }

        let baseURL = ServerConfig.shared.httpBaseURL
        guard let url = URL(string: "\(baseURL)/api/subscription/apple-verify") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "transactionId": String(transaction.id),
            "productId": productId,
            "originalTransactionId": String(transaction.originalID),
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("[Store] Server verify failed: status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool, ok {
                print("[Store] Server verified OK, product=\(productId)")
                return true
            }
            return false
        } catch {
            print("[Store] Server verify error: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    func monthlyProduct() -> Product? {
        products.first { $0.id.contains("monthly") }
    }

    func yearlyProduct() -> Product? {
        products.first { $0.id.contains("yearly") }
    }
}
