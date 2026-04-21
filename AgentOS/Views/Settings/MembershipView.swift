import SwiftUI
import StoreKit

struct MembershipView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var store = StoreService.shared
    @State private var usage: UsageData?
    @State private var purchaseChannel: String?
    @State private var message: String?
    @State private var selectedProduct: Product?
    @State private var showRenewConfirm = false

    private var isMember: Bool { authViewModel.plan != "free" }
    private var isIAPMember: Bool { isMember && purchaseChannel == "apple_iap" }
    private var isQRMember: Bool { isMember && purchaseChannel != nil && purchaseChannel != "apple_iap" }
    private var planExpires: Int64? { authViewModel.planExpires }
    private var daysLeft: Int {
        guard let exp = planExpires else { return 0 }
        return Int(ceil(Double(exp - Int64(Date().timeIntervalSince1970 * 1000)) / 86_400_000))
    }
    private var isExpired: Bool { isMember && planExpires != nil && planExpires! < Int64(Date().timeIntervalSince1970 * 1000) }
    private var graceDaysLeft: Int { isExpired ? 3 + daysLeft : 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status Card
                statusCard
                    .padding(.horizontal, 16)

                // Message toast
                if let msg = message {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .onTapGesture { message = nil }
                }

                // Benefits (free users only)
                if !isMember {
                    benefitsGrid
                        .padding(.horizontal, 16)
                }

                // Pricing / Renewal
                pricingSection
                    .padding(.horizontal, 16)

                // Restore purchases
                Button {
                    Task {
                        await store.restorePurchases()
                        await refreshPlan()
                    }
                } label: {
                    Text("恢复购买")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.top, 4)

                // Subscription terms (Apple review requirement)
                VStack(spacing: 4) {
                    Text("确认购买后将从 Apple ID 账户扣款。订阅到期前 24 小时内自动续费，可随时在「设置 → Apple ID → 订阅」中取消。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 4) {
                        Link("隐私政策", destination: URL(string: "https://www.tybbtech.com/zh/privacy-policy")!)
                        Text("·").foregroundStyle(AppTheme.textTertiary)
                        Link("用户协议", destination: URL(string: "https://www.tybbtech.com/zh/user-agreement")!)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#d97706"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)

                // Error
                if let err = store.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background)
        .navigationTitle("会员中心")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadProducts()
            await fetchUsage()
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isMember ? "★ 灵犀会员" : "免费版")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isMember ? .white : AppTheme.textSecondary)

            if isMember, let exp = planExpires {
                Text(daysLeft > 0
                     ? "到期：\(fmtDate(exp))（还有 \(daysLeft) 天）"
                     : daysLeft > -3
                        ? "⚠ 会员已过期，宽限期剩 \(3 + daysLeft) 天"
                        : "会员已过期")
                    .font(.system(size: 13))
                    .foregroundStyle(isMember ? .white.opacity(0.9) : AppTheme.textTertiary)
            }

            if let u = usage {
                HStack(spacing: 16) {
                    Text("对话 \(isMember || u.quotaMsg < 0 ? "不限" : "\(u.dailyMsg)次/\(u.quotaMsg)次")")
                    Text("搜索 \(u.quotaSearch < 0 ? "不限" : "\(u.dailySearch)次/\(u.quotaSearch)次")")
                }
                .font(.system(size: 12))
                .foregroundStyle(isMember ? .white.opacity(0.7) : AppTheme.textTertiary)

                Text("图片 \(u.quotaImage < 0 ? "不限" : "\(u.monthlyImage)张/\(u.quotaImage)张")(本月)")
                    .font(.system(size: 12))
                    .foregroundStyle(isMember ? .white.opacity(0.7) : AppTheme.textTertiary)

                Text("每日额度零点重置，图片按月重置")
                    .font(.system(size: 11))
                    .foregroundStyle(isMember ? .white.opacity(0.4) : AppTheme.textTertiary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            isMember
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#f59e0b"), Color(hex: "#d97706")], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(AppTheme.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isMember ? .clear : AppTheme.border, lineWidth: isMember ? 0 : 1)
        )
    }

    // MARK: - Benefits Grid

    private var benefitsGrid: some View {
        let items: [(icon: String, label: String, value: String)] = [
            ("💬", "对话", "300次/天"),
            ("🔍", "搜索", "30次/天"),
            ("🎨", "图片", "60张/月"),
            ("🤖", "主动关怀", "智能推送"),
            ("🔑", "BYOK", "自带Key"),
            ("📊", "回测", "无限次"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(items, id: \.label) { item in
                VStack(spacing: 4) {
                    Text(item.icon).font(.system(size: 20))
                    Text(item.label).font(.system(size: 12)).foregroundStyle(AppTheme.textTertiary)
                    Text(item.value).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 12) {
            // Grace period urgent notice
            if isExpired && graceDaysLeft > 0 {
                Text("⚠ 会员已过期，宽限期剩 \(graceDaysLeft) 天，请尽快续费！")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2)))
            }

            if isQRMember && !isExpired {
                // QR-scan member (not expired) viewing on iOS — can't renew here
                VStack(spacing: 8) {
                    Text("您的会员通过桌面端购买")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("续费请在桌面端会员中心操作")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isIAPMember && !isExpired {
                // IAP member — managed by Apple
                VStack(spacing: 8) {
                    Text("🍎")
                        .font(.system(size: 32))
                    Text("您的会员由 Apple 订阅管理")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("续费和取消请在系统设置中操作")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text("设置 → Apple ID → 订阅 → 灵犀会员")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if store.products.isEmpty {
                Text("加载商品信息中...")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.vertical, 20)
            } else {
                HStack(spacing: 12) {
                    ForEach(store.products, id: \.id) { product in
                        pricingCard(product: product)
                    }
                }

                // Renewal confirmation
                if showRenewConfirm, let product = selectedProduct {
                    VStack(spacing: 10) {
                        Text("续费后会员将延期到 \(newExpiryDate(product))，确认支付 \(product.displayPrice)？")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(4)

                        HStack(spacing: 8) {
                            Button {
                                Task { await doPurchase(product) }
                            } label: {
                                Text("确认支付")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(LinearGradient(colors: [Color(hex: "#f59e0b"), Color(hex: "#d97706")], startPoint: .leading, endPoint: .trailing))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Button {
                                showRenewConfirm = false
                            } label: {
                                Text("取消")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.border))
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(hex: "#f59e0b").opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#d97706"), lineWidth: 1))
                }

                if !showRenewConfirm {
                    // Buy / Renew button
                    Button {
                        guard let product = selectedProduct ?? store.monthlyProduct() else { return }
                        if isMember {
                            selectedProduct = product
                            showRenewConfirm = true
                        } else {
                            Task { await doPurchase(product) }
                        }
                    } label: {
                        Text(store.purchaseInProgress
                             ? "处理中..."
                             : "\(isMember ? "续费" : "立即升级") - \(selectedProduct?.displayPrice ?? store.monthlyProduct()?.displayPrice ?? "")")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(colors: [Color(hex: "#f59e0b"), Color(hex: "#d97706")], startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(store.purchaseInProgress)
                    .opacity(store.purchaseInProgress ? 0.6 : 1)
                }
            }
        }
    }

    private func pricingCard(product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id || (selectedProduct == nil && product == store.monthlyProduct())
        let isYearly = product.id.contains("yearly")

        return VStack(spacing: 6) {
            if isYearly && !isMember {
                Text("推荐")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#d97706"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(isMember ? (isYearly ? "续费 1 年" : "续费 1 个月") : (isYearly ? "年度会员" : "月度会员"))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)

            Text(product.displayPrice)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
            + Text(isYearly ? "/年" : "/月")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)

            if isMember {
                Text("到期延至 \(newExpiryDate(product))")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#d97706"))
            } else if isYearly {
                Text("相当于 ¥\(NSDecimalNumber(decimal: product.price / 12).intValue)/月")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#d97706"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(isSelected ? Color(hex: "#f59e0b").opacity(0.06) : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(hex: "#d97706") : AppTheme.border, lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            selectedProduct = product
            showRenewConfirm = false
        }
    }

    // MARK: - Actions

    private func doPurchase(_ product: Product) async {
        let ok = await store.purchase(product)
        if ok {
            message = "会员已生效！"
            await refreshPlan()
            showRenewConfirm = false
        }
    }

    private func refreshPlan() async {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else { return }
        if let data = await UsageService.shared.fetch(token: token) {
            let plan = data.plan == "member_builtin" || data.plan == "member_byok" ? "member" : data.plan
            authViewModel.setPlan(plan: plan, planExpires: data.planExpires, isByok: data.isByok)
            await fetchUsage()
        }
    }

    // MARK: - Usage Fetch

    private func fetchUsage() async {
        guard let token = try? await DatabaseService.shared.getSetting(key: "auth_token"),
              !token.isEmpty else { return }
        if let data = await UsageService.shared.fetch(token: token) {
            purchaseChannel = data.purchaseChannel
            usage = UsageData(
                dailyMsg: data.daily.msg,
                dailySearch: data.daily.search,
                monthlyImage: data.monthlyImage,
                quotaMsg: data.quota.msg,
                quotaSearch: data.quota.search,
                quotaImage: data.quota.image_monthly
            )
        }
    }

    // MARK: - Helpers

    private func fmtDate(_ ts: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ts) / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        return fmt.string(from: date)
    }

    private func newExpiryDate(_ product: Product) -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let base = (planExpires != nil && planExpires! > now) ? planExpires! : now
        let baseDate = Date(timeIntervalSince1970: Double(base) / 1000)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let newDate: Date
        if product.id.contains("yearly") {
            newDate = calendar.date(byAdding: .year, value: 1, to: baseDate) ?? baseDate
        } else {
            newDate = calendar.date(byAdding: .month, value: 1, to: baseDate) ?? baseDate
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd"
        return fmt.string(from: newDate)
    }
}

// MARK: - Usage Data Model

private struct UsageData {
    let dailyMsg: Int
    let dailySearch: Int
    let monthlyImage: Int
    let quotaMsg: Int
    let quotaSearch: Int
    let quotaImage: Int
}
