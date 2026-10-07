import SwiftUI
import StoreKit

@Observable @MainActor
final class CoderStore {
    static let shared = CoderStore()
    static let productIDs = ["com.agentosplus.coder.credits6", "com.agentosplus.coder.credits100", "com.agentosplus.coder.credits500"]
    #if CODER_CREATION_ONLY
    static let purchasesAllowed = false
    #else
    static let purchasesAllowed = true
    #endif
    var products: [Product] = []
    var credits: [String: Int] = [:]
    var balance: Int?
    var dailyBalance: Int?
    var shouldResumeCreation = false
    var enabled = false
    var loading = false
    var purchasing = false
    var message: String?
    private var listener: Task<Void, Never>?
    private var settling: Set<UInt64> = []

    private init() {
        listener = Task { @MainActor [weak self] in
            for await result in StoreKit.Transaction.updates {
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
            enabled = Self.purchasesAllowed && (config["enabled"] as? Bool == true)
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
        let server = ServerConfig.shared.httpBaseURL
        let account = try? await DatabaseService.shared.getSetting(key: "auth_token")
        do {
            let result = try await request("balance")
            let currentAccount = try? await DatabaseService.shared.getSetting(key: "auth_token")
            guard server == ServerConfig.shared.httpBaseURL, account == currentAccount else { return }
            balance = (result["balance"] as? [String: Any])?["total"] as? Int
            dailyBalance = (result["balance"] as? [String: Any])?["daily"] as? Int
        } catch {
            let currentAccount = try? await DatabaseService.shared.getSetting(key: "auth_token")
            guard server == ServerConfig.shared.httpBaseURL, account == currentAccount else { return }
            balance = nil
            message = error.localizedDescription
        }
    }

    func buy(_ product: Product) async {
        guard Self.purchasesAllowed, enabled, !purchasing, Self.productIDs.contains(product.id), product.type == .consumable else { return }
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
        guard Self.purchasesAllowed else { return }
        for await result in StoreKit.Transaction.unfinished { _ = await settle(result) }
    }

    @discardableResult private func settle(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        guard Self.purchasesAllowed else { return false }
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
            else if response["duplicate"] as? Bool != true {
                shouldResumeCreation = true
                message = "积分已到账，可以继续创作了。"
            }
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func loadOrders() async throws -> [CoderCreditOrder] {
        let response = try await request("orders")
        let data = try JSONSerialization.data(withJSONObject: response)
        return try JSONDecoder().decode(CoderOrdersResponse.self, from: data).orders
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
    let loadLedger: @MainActor () async throws -> [CoderLedgerGroup]
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
                    NavigationLink {
                        CoderOrdersView()
                    } label: {
                        HStack {
                            Label("充值 / 到账记录", systemImage: "receipt")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).background(AppTheme.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(store.purchasing)
                    NavigationLink {
                        CoderLedgerView(load: loadLedger)
                    } label: {
                        HStack {
                            Label("消耗明细", systemImage: "list.bullet.rectangle")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).background(AppTheme.primary.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(store.purchasing)
                    DisclosureGroup("积分说明与会员赠分") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let daily = store.dailyBalance, store.balance != nil {
                                Text("当前余额包含会员每日积分 \(daily) 分。")
                            }
                            Text("新用户注册赠送50积分；会员每日赠送15积分，按现有规则领取，累计上限90。")
                            Text("扣减顺序：每日额度 → 赠送 → 实付。会员充值赠分已计入商品显示的积分数量。")
                            Text("一般小修改约3积分、小工具约13积分、小游戏约180积分，仅供估算，实际按创作消耗计费。")
                            Text("App Store购买的退款由Apple处理。充值记录可查看每笔到账及退款状态。")
                        }.font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    Text("充值积分").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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


struct CoderLedgerResponse: Decodable {
    let ok: Bool
    let need: String?
    let groups: [CoderLedgerGroup]?
}

struct CoderLedgerGroup: Decodable, Identifiable {
    let projectId: String?
    let name: String
    let total: Int
    let count: Int
    let entries: [CoderLedgerEntry]
    var id: String { projectId ?? "_other" }
}

struct CoderLedgerEntry: Decodable {
    let spent: Int
    let model: String?
    let at: Double
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
    var modelLabel: String {
        switch model {
        case "deepseek-v4-pro": "精细模式"
        case "deepseek-v4-flash": "快速模式"
        default: "创作消耗"
        }
    }
}

struct CoderLedgerView: View {
    let load: @MainActor () async throws -> [CoderLedgerGroup]
    @State private var groups: [CoderLedgerGroup] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        List {
            if loading {
                ProgressView("正在加载消耗明细…")
            } else if let message {
                Text(message).foregroundStyle(.secondary)
                Button("重试") { Task { await reload() } }
            } else if groups.isEmpty {
                Text("还没有消耗记录").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(groups) { group in
                        DisclosureGroup {
                            ForEach(Array(group.entries.enumerated()), id: \.offset) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.element.date.formatted(date: .abbreviated, time: .shortened))
                                        Text(item.element.modelLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("−\(item.element.spent) 积分").monospacedDigit()
                                }.font(.subheadline).padding(.vertical, 4)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.name)
                                    Text("\(group.count) 笔记录").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("−\(group.total)").monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("按作品汇总 · 点开查看每笔消耗")
                }
            }
        }
        .navigationTitle("消耗明细")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true; message = nil
        defer { loading = false }
        do { groups = try await load() }
        catch { groups = []; message = error.localizedDescription }
    }
}


struct CoderOrdersResponse: Decodable { let orders: [CoderCreditOrder] }
struct CoderCreditOrder: Decodable, Identifiable {
    let id: String
    let credits: Int
    let bonus: Int
    let total: Int
    let status: String
    let channel: String?
    let createdAt: Double
    let paidAt: Double?
    let amountYuan: Double?
    var date: Date { Date(timeIntervalSince1970: (paidAt ?? createdAt) / 1000) }
    var statusText: String {
        switch status {
        case "paid": "已到账"
        case "refunded": "已退款"
        case "paying": "处理中"
        case "created": "未支付"
        default: "待核对"
        }
    }
}
struct CoderOrdersView: View {
    @State private var orders: [CoderCreditOrder] = []
    @State private var loading = false
    @State private var message: String?
    var body: some View {
        List {
            if loading { ProgressView("正在加载到账记录…") }
            else if let message {
                Text(message).foregroundStyle(.secondary)
                Button("重试") { Task { await reload() } }
            } else if orders.isEmpty { Text("还没有充值记录").foregroundStyle(.secondary) }
            else {
                Section {
                    ForEach(orders) { order in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(order.total) 积分").font(.headline)
                                Spacer()
                                Text(order.statusText).foregroundStyle(.secondary)
                            }
                            Text("购买 \(order.credits) + 赠送 \(order.bonus) 积分").font(.subheadline)
                            Text(order.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            if order.channel == "APPLE_CREDITS" {
                                Text("App Store购买 · 实付金额以Apple账单为准").font(.caption).foregroundStyle(.secondary)
                            } else if let amount = order.amountYuan {
                                Text("网页充值 · ¥\(amount.formatted())").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }
                } header: { Text("最近20笔充值 · 含赠送积分") }
                footer: { Text("记录中的积分为该订单原始积分数；已退款订单不代表当前可用余额。注册赠分和会员每日积分不属于充值订单。") }
            }
        }
        .navigationTitle("充值 / 到账记录")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }
    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true; message = nil
        defer { loading = false }
        do { orders = try await CoderStore.shared.loadOrders() }
        catch { orders = []; message = error.localizedDescription }
    }
}
