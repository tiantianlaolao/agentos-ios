import SwiftUI

struct QuotaBarView: View {
    let authViewModel: AuthViewModel
    let refreshTrigger: Int

    @State private var usage: UsageResponse?

    var body: some View {
        Group {
            if let usage, authViewModel.hasRealLogin, usage.plan == "free", usage.quota.msg >= 0 {
                let remaining = max(0, usage.quota.msg - usage.daily.msg)
                let isLow = remaining <= 3
                HStack(spacing: 4) {
                    Text("今日剩余 \(remaining) 条消息")
                        .font(.system(size: 11))
                        .foregroundStyle(isLow ? Color(hex: "#E89661") : AppTheme.textTertiary)
                    if isLow {
                        Text("· 升级会员解锁日常不限")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#E89661"))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(isLow ? Color(hex: "#FFF8F0") : Color(hex: "#FAFAFA"))
            } else {
                // Invisible placeholder — keeps body non-empty so .task modifier attaches.
                // Without this, SwiftUI treats an initially empty Group as EmptyView and
                // the .task never fires, so refresh()/retry never runs.
                Color.clear.frame(height: 0)
            }
        }
        .task(id: refreshTrigger) {
            // Retry up to 5 times with backoff — ServerConfig.shared.update() runs async
            // on app launch, so the first attempt may hit the default (prod) URL before
            // the test server URL is resolved. Retries give it time to settle.
            for attempt in 0..<5 {
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(2))
                }
                let token = try? await DatabaseService.shared.getSetting(key: "auth_token")
                guard let t = token, !t.isEmpty else { continue }
                if let result = await UsageService.shared.fetch(token: t) {
                    await MainActor.run {
                        self.usage = result
                        authViewModel.setPlan(plan: result.plan, planExpires: result.planExpires, isByok: result.isByok)
                    }
                    return
                }
            }
        }
    }
}
