import SwiftUI
import StoreKit

@Observable @MainActor
final class CoderStore {
    static let shared = CoderStore()
    static let productIDs = ["com.agentosplus.coder.credits6", "com.agentosplus.coder.credits100", "com.agentosplus.coder.credits500"]
    var products: [Product] = []
    var credits: [String: Int] = [:]
    var balance: Int?
    var enabled = false
    var loading = false
    var purchasing = false
    var message: String?
    private var listener: Task<Void, Never>?
    private var settling: Set<UInt64> = []

    private init() {
        listener = Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                _ = await self.settle(result)
            }
        }
    }

    func load() async {
        guard !loading else { return }
        loading = true; message = nil; balance = nil; enabled = false; products = []
        defer { loading = false }
        do {
            let config = try await request("apple/products")
            enabled = config["enabled"] as? Bool == true
            credits = [:]
            for row in config["products"] as? [[String: Any]] ?? [] {
                if let id = row["id"] as? String, Self.productIDs.contains(id), let total = row["total"] as? Int { credits[id] = total }
            }
            if enabled {
                products = try await Product.products(for: Self.productIDs).filter { $0.type == .consumable }.sorted { $0.price < $1.price }
                if products.isEmpty { message = "暂时无法获取商品价格，请稍后重试" }
            } else { products = []; message = "积分购买暂未开放，已有积分可以继续使用。" }
            await recover()
            await refreshBalance()
        } catch { enabled = false; products = []; message = error.localizedDescription }
    }

    func refreshBalance() async {
        do {
            let result = try await request("balance")
            balance = (result["balance"] as? [String: Any])?["total"] as? Int
        } catch { message = error.localizedDescription }
    }

    func buy(_ product: Product) async {
        guard enabled, !purchasing, Self.productIDs.contains(product.id), product.type == .consumable else { return }
        purchasing = true; message = nil
        defer { purchasing = false }
        do {
            // This server-created token binds the signed transaction to this AIHEY
            // account, product, and membership bonus at purchase time.
            let intent = try await request("apple/prepare", body: ["productId": product.id])
            guard let text = intent["appAccountToken"] as? String, let account = UUID(uuidString: text) else { throw CoderError.message("暂时无法创建购买请求") }
            switch try await product.purchase(options: [.appAccountToken(account)]) {
            case .success(let result): _ = await settle(result)
            case .pending: message = "购买待确认，确认后积分会自动入账。"
            case .userCancelled: break
            @unknown default: message = "购买尚未完成，请稍后检查。"
            }
        } catch { message = error.localizedDescription }
    }

    func recover() async {
        for await result in Transaction.unfinished { _ = await settle(result) }
    }

    @discardableResult private func settle(_ result: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { return false }
        guard !settling.contains(transaction.id) else { return false }
        settling.insert(transaction.id)
        defer { settling.remove(transaction.id) }
        do {
            let response = try await request("apple/verify", body: ["jws": result.jwsRepresentation])
            guard response["ok"] as? Bool == true else { throw CoderError.message("积分尚未入账，请重试") }
            // Never finish on an unverified transaction, a network failure, or a
            // different AIHEY account. StoreKit will keep it for recovery.
            await transaction.finish()
            balance = (response["balance"] as? [String: Any])?["total"] as? Int
            if response["revoked"] as? Bool == true { message = "这笔购买已退款或撤销。" }
            else if response["duplicate"] as? Bool != true { message = "积分已到账，可以继续创作了。" }
            return true
        } catch { message = error.localizedDescription; return false }
    }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        guard let token = try await DatabaseService.shared.getSetting(key: "auth_token"), !token.isEmpty else { throw CoderError.message("请先登录 AIHEY") }
        guard let url = URL(string: ServerConfig.shared.httpBaseURL + "/api/coder-app/" + path) else { throw CoderError.message("连接地址无效") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoderError.message("服务响应异常，请稍后重试") }
        guard (response as? HTTPURLResponse)?.statusCode == 200, value["ok"] as? Bool == true else {
            throw CoderError.message(value["error"] as? String ?? "操作未完成，请稍后重试")
        }
        return value
    }
}

struct CoderCreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CoderStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "bolt.fill").font(.largeTitle).foregroundStyle(AppTheme.primary)
                    if let balance = store.balance { Text("\(balance) 积分").font(.largeTitle.bold()) }
                    Text("积分用于造物台创作和修改作品，与聊天会员额度分开计算。")
                        .foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
                    if store.loading { ProgressView() }
                    ForEach(store.products) { product in
                        Button { Task { await store.buy(product) } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(store.credits[product.id] ?? 0) 积分").font(.headline)
                                    Text("已按当前会员身份计算赠分").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice).font(.headline)
                            }.padding(18).background(AppTheme.primary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }.disabled(store.purchasing || store.loading || store.credits[product.id] == nil)
                    }
                    if store.purchasing { ProgressView("正在处理购买…") }
                    if let message = store.message { Text(message).font(.callout).multilineTextAlignment(.center) }
                    Button("刷新商品与余额") { Task { await store.load() } }.disabled(store.loading || store.purchasing)
                    Button("检查未到账购买") { Task { await store.recover(); await store.refreshBalance() } }.disabled(store.purchasing)
                    Text("一次性购买，不自动续费。购买前会显示 Apple 确认页面；已用完的消耗型积分不会重复恢复。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .navigationTitle("造物积分")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(store.purchasing) } }
            .task { await store.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.recover(); await store.refreshBalance() } } }
        }.interactiveDismissDisabled(store.purchasing)
    }
}
