import SwiftUI

struct InviteView: View {
    @Bindable var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var status: InviteStatus?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showPoster = false
    @State private var copiedToast: String?
    @State private var isRegenerating = false
    @State private var showRegenConfirm = false

    private var code: String { status?.inviteCode ?? "" }
    private var shareURL: String {
        guard !code.isEmpty else { return "" }
        return InviteService.shared.shareURL(code: code)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView().padding(.top, 40)
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding()
                    }
                    if let status, !code.isEmpty {
                        codeCard
                        progressCard(status: status)
                        shareButtons
                        rulesBlock
                    }
                }
                .padding(16)
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.tr("invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                    }
                }
            }
            .task { await fetchStatus() }
            .sheet(isPresented: $showPoster) { posterSheet }
            .alert(L10n.tr("invite.regenerateTitle"), isPresented: $showRegenConfirm) {
                Button(L10n.tr("common.cancel"), role: .cancel) {}
                Button(L10n.tr("common.confirm"), role: .destructive) { Task { await regenerate() } }
            } message: {
                Text(L10n.tr("invite.regenerateConfirm"))
            }
            .overlay(alignment: .center) {
                if let toast = copiedToast {
                    Text(toast)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Code Card

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text(L10n.tr("invite.codeLabel"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
            Text(code)
                .font(.system(size: 44, weight: .heavy, design: .monospaced))
                .kerning(8)
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                Button(action: copyCode) {
                    Text(L10n.tr("invite.copyCode"))
                        .font(.system(size: 13))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.white.opacity(0.22))
                        .foregroundStyle(.white)
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                }
                Button(action: { showRegenConfirm = true }) {
                    Text(isRegenerating ? L10n.tr("invite.regenerating") : L10n.tr("invite.regenerate"))
                        .font(.system(size: 13))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }
                .disabled(isRegenerating)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 18)
        .background(LinearGradient(colors: [Color(hex: "#FFA040"), Color(hex: "#FF6B1A")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Progress Card

    private func progressCard(status: InviteStatus) -> some View {
        let earnedDays = status.rewards
            .filter { $0.reward_type == "register_inviter" && $0.status == "confirmed" }
            .reduce(0) { $0 + $1.days }
        let pendingFP = status.rewards.filter { $0.reward_type == "first_purchase" && $0.status == "locked" }.count

        return VStack(spacing: 8) {
            progressRow(L10n.tr("invite.monthlyUsed"), value: "\(status.monthly.used) / \(status.monthly.limit)")
            progressRow(L10n.tr("invite.earnedDays"), value: "\(earnedDays) \(L10n.tr("invite.days"))")
            if pendingFP > 0 {
                progressRow(L10n.tr("invite.pendingFirstPurchase"), value: "\(pendingFP)")
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func progressRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(AppTheme.textTertiary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.textPrimary)
        }
    }

    // MARK: - Share Buttons

    private var shareButtons: some View {
        VStack(spacing: 10) {
            Button(action: systemShare) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(L10n.tr("invite.shareToFriend"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "#FF6B1A"))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: { showPoster = true }) {
                HStack {
                    Image(systemName: "photo")
                    Text(L10n.tr("invite.showPoster"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(AppTheme.primary)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.primary.opacity(0.4), lineWidth: 1))
            }
        }
    }

    // MARK: - Rules

    private var rulesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("· " + L10n.tr("invite.rule1"))
            Text("· " + L10n.tr("invite.rule2"))
            Text("· " + L10n.tr("invite.rule3"))
        }
        .font(.system(size: 12))
        .foregroundStyle(AppTheme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(AppTheme.border), alignment: .top)
    }

    // MARK: - Poster Sheet

    private var posterSheet: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let url = InviteService.shared.posterURL(code: code) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let img):
                        img.resizable().scaledToFit().padding(20)
                    case .failure:
                        Text("Failed to load poster").foregroundStyle(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            Button(action: { showPoster = false }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func fetchStatus() async {
        guard let token = await loadToken() else {
            isLoading = false
            errorMessage = L10n.tr("invite.fetchFailed")
            return
        }
        isLoading = true
        let s = await InviteService.shared.getStatus(token: token)
        if let s {
            status = s
        } else {
            errorMessage = L10n.tr("invite.fetchFailed")
        }
        isLoading = false
    }

    private func loadToken() async -> String? {
        // Read auth token from DatabaseService settings (saved by AuthViewModel.saveAuth).
        // DatabaseService is an actor, so must await across actor boundary.
        (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? nil
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        showToast(L10n.tr("invite.copied"))
    }

    private func systemShare() {
        guard !code.isEmpty else { return }
        let raw = L10n.tr("invite.shareText")
        let text = raw
            .replacingOccurrences(of: "{code}", with: code)
            .replacingOccurrences(of: "{url}", with: shareURL)
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            // Find the topmost presented view controller to attach to
            var top = root
            while let presented = top.presentedViewController { top = presented }
            top.present(activity, animated: true)
        }
    }

    private func regenerate() async {
        guard let token = await loadToken() else { return }
        isRegenerating = true
        let r = await InviteService.shared.regenerate(token: token)
        isRegenerating = false
        if r.ok {
            await fetchStatus()
        } else if let err = r.error {
            errorMessage = err
        }
    }

    private func showToast(_ text: String) {
        copiedToast = text
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copiedToast = nil
        }
    }
}
