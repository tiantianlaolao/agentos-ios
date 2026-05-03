import SwiftUI

struct SettingsView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var viewModel = SettingsViewModel()

    // MARK: - Data

    // External Agent mode retired 2026-04-19 — only builtin remains
    private var modes: [(key: ConnectionMode, titleKey: String, descKey: String, icon: String, color: Color)] {
        [
            (.builtin, "settings.builtin", "settings.builtinDesc", "cpu", Color(hex: "#2d7d46")),
        ]
    }

    private let models: [(key: String, label: String)] = [
        ("deepseek", "DeepSeek"),
    ]

    private let providers: [(key: LLMProvider, label: String)] = [
        (.deepseek, "DeepSeek"),
    ]

    private let languages: [(key: String, label: String)] = [
        ("zh", "中文"),
        ("en", "English"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Desktop companion banner
                desktopBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // Current mode indicator bar
                currentModeBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                // Account section
                accountSection
                    .padding(.bottom, 8)

                // Membership entry (only when logged in)
                if authViewModel.isLoggedIn {
                    membershipEntry
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    changelogEntry
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }

                // Connection Mode
                settingsSection(header: L10n.tr("settings.connectionMode")) {
                    connectionModeCards
                }

                // Mode-specific configuration
                modeConfigSection

                // Language
                settingsSection(header: L10n.tr("settings.language")) {
                    languageRow
                }

                // Privacy & Compliance — R4 personalization toggle + P1-C complaint entry
                settingsSection(header: L10n.tr("settings.privacySection")) {
                    privacyRows
                }

                // Save button
                saveButton
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                // Version
                versionInfo
                    .padding(.top, 16)

                // Logout & Delete Account
                if authViewModel.isLoggedIn {
                    logoutButton
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    deleteAccountButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                } else {
                    Spacer()
                        .frame(height: 32)
                }
            }
        }
        .background(AppTheme.background)
        .navigationTitle(L10n.tr("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadSettings()
        }
        .alert(L10n.tr("settings.betaRequired"), isPresented: $showBetaAlert) {
            TextField(L10n.tr("settings.betaCodePlaceholder"), text: $betaCode)
                .autocapitalization(.allCharacters)
            Button(betaLoading ? L10n.tr("settings.betaActivating") : L10n.tr("settings.betaActivate")) {
                activateBeta()
            }
            .disabled(betaLoading)
            Button(L10n.tr("chat.cancel"), role: .cancel) {
                betaCode = ""
                betaError = ""
            }
        } message: {
            Text(betaError.isEmpty ? L10n.tr("settings.betaRequiredDesc") : betaError)
        }
        .sheet(isPresented: $showCSWebView) {
            NavigationStack {
                CSWebView(url: ServerConfig.shared.httpBaseURL + "/cs")
                    .navigationTitle("在线客服")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") { showCSWebView = false }
                        }
                    }
            }
        }
    }

    // MARK: - Current Mode Bar

    private var currentModeBar: some View {
        let modeInfo = modes.first { $0.key == viewModel.mode }
        let modeColor = modeInfo?.color ?? AppTheme.success
        let modeName = L10n.tr(modeInfo?.titleKey ?? "settings.builtin")

        return HStack(spacing: 10) {
            Circle()
                .fill(modeColor)
                .frame(width: 8, height: 8)
            Text(L10n.tr("settings.currentMode"))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
            Text(modeName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(modeColor)
            if viewModel.mode == .builtin && viewModel.builtinSubMode == "byok" {
                Text("(\(L10n.tr("settings.builtinByok")))")
                    .font(.system(size: 11))
                    .foregroundStyle(modeColor.opacity(0.8))
            }
            // External Agent label retired 2026-04-19
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(modeColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(modeColor.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Account Section

    @State private var showLoginSheet = false
    @State private var showCSWebView = false
    @State private var showDeleteAccountAlert = false
    @State private var deleteAccountPassword = ""
    @State private var showBetaAlert = false
    @State private var betaCode = ""
    @State private var betaLoading = false
    @State private var betaError = ""
    @State private var showComplaintSheet = false
    @State private var personalizationFailMessage = ""
    @State private var showPersonalizationFailAlert = false
    @State private var pendingAgentId = ""

    // MARK: - Membership Entry

    private var membershipEntry: some View {
        NavigationLink {
            MembershipView(authViewModel: authViewModel)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#f59e0b"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("会员中心")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(authViewModel.plan == "free" ? "免费版" : "灵犀会员")
                        .font(.system(size: 12))
                        .foregroundStyle(authViewModel.plan == "free" ? AppTheme.textTertiary : Color(hex: "#d97706"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var changelogEntry: some View {
        Button {
            // Open public changelog page in browser. This counts as
            // "viewed" — ack the post mode for the latest version so
            // the red dot clears.
            ChangelogService.shared.openChangelogPage()
            if let latest = ChangelogService.shared.response?.latest_version {
                Task {
                    await ChangelogService.shared.ack(version: latest, mode: .post, action: .clicked_detail)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#0891b2"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("版本日志")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(changelogSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
                if ChangelogService.shared.hasUnseenChangelog {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var changelogSubtitle: String {
        let cur = ChangelogService.shared.currentVersion
        if let latest = ChangelogService.shared.response?.latest_version, latest != cur {
            return "当前 v\(cur) · 最新 v\(latest)"
        }
        return "当前 v\(cur)"
    }

    private var accountSection: some View {
        Group {
            if authViewModel.isLoggedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.loggedInAs", ["phone": ""]))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(authViewModel.savedPhone.isEmpty ? "User" : authViewModel.savedPhone)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            } else {
                // Anonymous mode - show login button
                Button {
                    showLoginSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(AppTheme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.notLoggedIn"))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(L10n.tr("settings.loginOrRegister"))
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showLoginSheet) {
                    LoginView(authViewModel: authViewModel)
                }
            }
        }
    }

    // MARK: - Connection Mode Cards

    private var connectionModeCards: some View {
        VStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.key) { index, m in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.mode = m.key
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Radio circle
                        ZStack {
                            Circle()
                                .stroke(viewModel.mode == m.key ? AppTheme.primary : AppTheme.textTertiary.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                            if viewModel.mode == m.key {
                                Circle()
                                    .fill(AppTheme.primary)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        // Icon
                        Image(systemName: m.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(m.color)
                            .frame(width: 24)

                        // Text
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L10n.tr(m.titleKey))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(L10n.tr(m.descKey))
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(viewModel.mode == m.key ? AppTheme.primary.opacity(0.06) : Color.clear)
                }
                .buttonStyle(.plain)

                if index < modes.count - 1 {
                    Divider()
                        .background(AppTheme.divider)
                        .padding(.leading, 52)
                }
            }
        }
    }

    // MARK: - Mode Config Section

    @ViewBuilder
    private var modeConfigSection: some View {
        switch viewModel.mode {
        case .builtin:
            builtinConfig
        case .agent:
            agentConfig
        case .openclaw:
            openclawConfig
        case .copaw:
            copawConfig
        case .byok:
            byokConfig
        }
    }

    // MARK: - Built-in Agent Config

    private var builtinConfig: some View {
        VStack(spacing: 0) {
            // Sub-mode toggle: Free / BYOK
            settingsSection(header: L10n.tr("settings.mode")) {
                VStack(spacing: 0) {
                    subModeRow(
                        title: L10n.tr("settings.builtinFree"),
                        subtitle: L10n.tr("settings.builtinFreeDesc"),
                        selected: viewModel.builtinSubMode == "free",
                        isLast: false
                    ) {
                        viewModel.builtinSubMode = "free"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: L10n.tr("settings.builtinByok"),
                        subtitle: L10n.tr("settings.byokDesc"),
                        selected: viewModel.builtinSubMode == "byok",
                        isLast: true
                    ) {
                        viewModel.builtinSubMode = "byok"
                    }
                }
            }

            if viewModel.builtinSubMode == "free" {
                // Model dropdown
                settingsSection(header: L10n.tr("settings.model")) {
                    dropdownRow(
                        icon: "brain",
                        label: L10n.tr("settings.model"),
                        options: models,
                        selected: viewModel.selectedModel
                    ) {
                        viewModel.selectedModel = $0
                    }
                }
            } else {
                byokConfig
            }
        }
    }

    // MARK: - BYOK Config

    private var byokConfig: some View {
        settingsSection(header: L10n.tr("settings.provider")) {
            VStack(spacing: 0) {
                // Provider dropdown
                dropdownRow(
                    icon: "server.rack",
                    label: L10n.tr("settings.provider"),
                    options: providers.map { (key: $0.key.rawValue, label: $0.label) },
                    selected: viewModel.provider.rawValue
                ) {
                    viewModel.provider = LLMProvider(rawValue: $0) ?? .deepseek
                }

                Divider().background(AppTheme.divider).padding(.leading, 52)

                // API Key field
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 24)
                    Text(L10n.tr("settings.apiKey"))
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    SecureField(L10n.tr("settings.apiKeyPlaceholder"), text: $viewModel.apiKey)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Agent Config (unified)

    private var agentConfig: some View {
        VStack(spacing: 0) {
            // Deploy mode only (direct connect removed)
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
                Text(L10n.tr("settings.agentDeployHint"))
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Beta Gate

    private func checkBetaAndSelect(agentId: String) {
        let serverUrl = viewModel.serverUrl
        Task {
            do {
                let token = try await DatabaseService.shared.getSetting(key: "auth_token") ?? ""
                guard !token.isEmpty else {
                    // No token, show beta alert
                    await MainActor.run {
                        pendingAgentId = agentId
                        showBetaAlert = true
                    }
                    return
                }
                var request = URLRequest(url: URL(string: "\(serverUrl)/hosted/beta-status")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let hasBeta = json["hasBeta"] as? Bool, hasBeta {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.agentId = agentId
                        }
                    }
                } else {
                    await MainActor.run {
                        pendingAgentId = agentId
                        showBetaAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    pendingAgentId = agentId
                    showBetaAlert = true
                }
            }
        }
    }

    private func activateBeta() {
        guard !betaCode.isEmpty else { return }
        let serverUrl = viewModel.serverUrl
        betaLoading = true
        betaError = ""

        Task {
            do {
                let token = try await DatabaseService.shared.getSetting(key: "auth_token") ?? ""
                var request = URLRequest(url: URL(string: "\(serverUrl)/hosted/beta-activate")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["code": betaCode.trimmingCharacters(in: .whitespaces)])
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success {
                    await MainActor.run {
                        showBetaAlert = false
                        betaCode = ""
                        betaError = ""
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.agentId = pendingAgentId
                        }
                    }
                } else {
                    let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    await MainActor.run {
                        betaError = errorMsg ?? L10n.tr("settings.betaFailed")
                    }
                }
            } catch {
                await MainActor.run {
                    betaError = L10n.tr("settings.betaFailed")
                }
            }
            await MainActor.run { betaLoading = false }
        }
    }

    /// Agent selection row with icon and radio
    private func agentSelectionRow(title: String, icon: String, color: Color, selected: Bool, isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(selected ? AppTheme.primary : AppTheme.textTertiary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 9, height: 9)
                    }
                }

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(selected ? AppTheme.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - OpenClaw Config

    private var openclawConfig: some View {
        VStack(spacing: 0) {
            // URL/Token fields
            settingsSection(header: L10n.tr("settings.openclawUrl")) {
                VStack(spacing: 0) {
                    textFieldRow(
                        icon: "link",
                        label: L10n.tr("settings.openclawUrl"),
                        placeholder: L10n.tr("settings.openclawUrlPlaceholder"),
                        text: $viewModel.openclawUrl,
                        isSecure: false
                    )
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    textFieldRow(
                        icon: "lock.fill",
                        label: L10n.tr("settings.openclawToken"),
                        placeholder: L10n.tr("settings.openclawTokenPlaceholder"),
                        text: $viewModel.openclawToken,
                        isSecure: true
                    )
                }
            }
        }
    }

    // MARK: - CoPaw Config

    private var copawConfig: some View {
        VStack(spacing: 0) {
            // Level 1: Deploy vs Self-hosted
            settingsSection(header: L10n.tr("settings.deployMode")) {
                VStack(spacing: 0) {
                    subModeRow(
                        title: L10n.tr("settings.copawDeploy"),
                        subtitle: L10n.tr("settings.copawDeployDesc"),
                        selected: viewModel.copawSubMode == "deploy",
                        isLast: false
                    ) {
                        viewModel.copawSubMode = "deploy"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: L10n.tr("settings.copawSelfhosted"),
                        subtitle: L10n.tr("settings.copawSelfhostedDesc"),
                        selected: viewModel.copawSubMode == "selfhosted",
                        isLast: true
                    ) {
                        viewModel.copawSubMode = "selfhosted"
                    }
                }
            }

            if viewModel.copawSubMode == "deploy" {
                // Deploy hint: deploy on desktop first
                Text(L10n.tr("settings.copawDeployDesktopHint"))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                // Level 2 under Self-hosted: Remote / Local
                settingsSection(header: L10n.tr("settings.copawSelfhosted")) {
                    VStack(spacing: 0) {
                        subModeRow(
                            title: L10n.tr("settings.copawSelfhostedRemote"),
                            subtitle: "",
                            selected: viewModel.copawSelfhostedType == "remote",
                            isLast: false
                        ) {
                            viewModel.copawSelfhostedType = "remote"
                        }
                        Divider().background(AppTheme.divider).padding(.leading, 52)
                        subModeRow(
                            title: L10n.tr("settings.copawSelfhostedLocal"),
                            subtitle: "",
                            selected: viewModel.copawSelfhostedType == "local",
                            isLast: true
                        ) {
                            viewModel.copawSelfhostedType = "local"
                        }
                    }
                }

                // Show URL/Token fields for remote, localhost hint for local
                if viewModel.copawSelfhostedType == "remote" {
                    settingsSection(header: L10n.tr("settings.copawUrl")) {
                        VStack(spacing: 0) {
                            textFieldRow(
                                icon: "link",
                                label: L10n.tr("settings.copawUrl"),
                                placeholder: L10n.tr("settings.copawUrlPlaceholder"),
                                text: $viewModel.copawUrl,
                                isSecure: false
                            )
                            Divider().background(AppTheme.divider).padding(.leading, 52)
                            textFieldRow(
                                icon: "lock.fill",
                                label: L10n.tr("settings.copawToken"),
                                placeholder: L10n.tr("settings.copawTokenPlaceholder"),
                                text: $viewModel.copawToken,
                                isSecure: true
                            )
                        }
                    }
                } else {
                    settingsSection(header: L10n.tr("settings.copawUrl")) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(width: 24)
                            Text("http://localhost:8088")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - CoPaw Model Selection

    private var copawModelSection: some View {
        VStack(spacing: 0) {
            settingsSection(header: L10n.tr("settings.model")) {
                VStack(spacing: 0) {
                    subModeRow(
                        title: L10n.tr("settings.copawModelDefault"),
                        subtitle: "",
                        selected: viewModel.copawDeployModelMode == "default",
                        isLast: false
                    ) {
                        viewModel.copawDeployModelMode = "default"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: L10n.tr("settings.copawModelCustom"),
                        subtitle: "",
                        selected: viewModel.copawDeployModelMode == "custom",
                        isLast: true
                    ) {
                        viewModel.copawDeployModelMode = "custom"
                    }
                }
            }

            if viewModel.copawDeployModelMode == "custom" {
                settingsSection(header: L10n.tr("settings.copawDeployProvider")) {
                    VStack(spacing: 0) {
                        // Provider dropdown
                        dropdownRow(
                            icon: "server.rack",
                            label: L10n.tr("settings.copawDeployProvider"),
                            options: providers.map { (key: $0.key.rawValue, label: $0.label) },
                            selected: viewModel.copawDeployProvider
                        ) {
                            viewModel.copawDeployProvider = $0
                        }

                        Divider().background(AppTheme.divider).padding(.leading, 52)

                        // API Key field
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(width: 24)
                            Text(L10n.tr("settings.copawDeployApiKey"))
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            SecureField(L10n.tr("settings.copawDeployApiKeyPlaceholder"), text: $viewModel.copawDeployApiKey)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().background(AppTheme.divider).padding(.leading, 52)

                        // Model name field
                        HStack(spacing: 12) {
                            Image(systemName: "brain")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textTertiary)
                                .frame(width: 24)
                            Text(L10n.tr("settings.copawDeployModel"))
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            TextField(L10n.tr("settings.copawDeployModelPlaceholder"), text: $viewModel.copawDeployModel)
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 180)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    // MARK: - Language Row (Dropdown)

    private var languageRow: some View {
        dropdownRow(
            icon: "globe",
            label: L10n.tr("settings.language"),
            options: languages,
            selected: viewModel.locale
        ) {
            viewModel.locale = $0
        }
    }

    // MARK: - Privacy Rows (R4 + P1-C)

    private var privacyRows: some View {
        VStack(spacing: 10) {
            // R4 personalization toggle
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("settings.personalizationTitle"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L10n.tr("settings.personalizationDesc"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineSpacing(3)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { viewModel.personalizationEnabled },
                    set: { newValue in
                        Task {
                            let ok = await viewModel.togglePersonalization(newValue)
                            if !ok {
                                personalizationFailMessage = L10n.tr("settings.personalizationFailMsg")
                                showPersonalizationFailAlert = true
                            }
                        }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.primary)
                .disabled(viewModel.personalizationLoading)
            }
            .padding(14)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // P1-C complaint entry
            Button {
                showComplaintSheet = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("settings.complaintTitle"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(L10n.tr("settings.complaintDesc"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(14)
                .background(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showComplaintSheet) {
            NavigationStack {
                ComplaintFormView(authViewModel: authViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.tr("complaint.ok")) {
                                showComplaintSheet = false
                            }
                        }
                    }
            }
        }
        .alert(L10n.tr("settings.personalizationFailTitle"), isPresented: $showPersonalizationFailAlert) {
            Button(L10n.tr("complaint.ok")) {}
        } message: {
            Text(personalizationFailMessage)
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            Task { await viewModel.saveSettings() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else if viewModel.showSaved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.tr("settings.savedDone"))
                } else {
                    Text(L10n.tr("settings.save"))
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(viewModel.showSaved ? AppTheme.success : AppTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(viewModel.isSaving)
    }

    // MARK: - Desktop Banner

    private var desktopBanner: some View {
        Button {
            if let url = URL(string: "https://www.tybbtech.com") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 22))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("settings.desktopBannerTitle"))
                        .font(AppTheme.bodyFont.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L10n.tr("settings.desktopBannerDesc"))
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Text("www.tybbtech.com")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accent)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(14)
            .background(AppTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }

    // MARK: - Version

    private var versionInfo: some View {
        let isZh = L10n.shared.locale == "zh"
        let agreementURL = isZh
            ? "https://www.tybbtech.com/zh/user-agreement"
            : "https://www.tybbtech.com/en/user-agreement"
        let privacyURL = isZh
            ? "https://www.tybbtech.com/zh/privacy-policy"
            : "https://www.tybbtech.com/en/privacy-policy"

        return VStack(spacing: 6) {
            Text("AgentOS iOS v3.0.0")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)

            HStack(spacing: 0) {
                Link(L10n.tr("settings.userAgreement"), destination: URL(string: agreementURL)!)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textBrand)
                Text(" · ")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                Link(L10n.tr("settings.privacyPolicy"), destination: URL(string: privacyURL)!)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textBrand)
                Text(" · ")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textTertiary)
                Button("在线客服") {
                    showCSWebView = true
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textBrand)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            Task { await authViewModel.logout() }
        } label: {
            Text(L10n.tr("settings.logout"))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppTheme.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.error.opacity(0.3), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Delete Account

    private var deleteAccountButton: some View {
        Button {
            deleteAccountPassword = ""
            showDeleteAccountAlert = true
        } label: {
            Text(L10n.tr("settings.deleteAccount"))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .alert(L10n.tr("settings.deleteAccountTitle"), isPresented: $showDeleteAccountAlert) {
            SecureField(L10n.tr("settings.deleteAccountPasswordPlaceholder"), text: $deleteAccountPassword)
            Button(L10n.tr("settings.deleteAccountConfirm"), role: .destructive) {
                Task {
                    let success = await authViewModel.deleteAccount(password: deleteAccountPassword)
                    if !success && !authViewModel.deleteAccountError.isEmpty {
                        authViewModel.errorMessage = authViewModel.deleteAccountError
                    }
                }
            }
            Button(L10n.tr("settings.cancel"), role: .cancel) { }
        } message: {
            Text(L10n.tr("settings.deleteAccountWarning"))
        }
    }

    // MARK: - Reusable Components

    /// Section container with optional header
    private func settingsSection<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            content()
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    /// Sub-mode radio row
    private func subModeRow(title: String, subtitle: String, selected: Bool, isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                action()
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(selected ? AppTheme.primary : AppTheme.textTertiary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle()
                            .fill(AppTheme.primary)
                            .frame(width: 9, height: 9)
                    }
                }
                .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(selected ? AppTheme.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Dropdown row using Menu
    private func dropdownRow(icon: String, label: String, options: [(key: String, label: String)], selected: String, onChange: @escaping (String) -> Void) -> some View {
        let selectedLabel = options.first(where: { $0.key == selected })?.label ?? selected

        return Menu {
            ForEach(options, id: \.key) { opt in
                Button {
                    onChange(opt.key)
                } label: {
                    HStack {
                        Text(opt.label)
                        if opt.key == selected {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(selectedLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Text field row for URL/Token inputs
    private func textFieldRow(icon: String, label: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(width: 24)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.surfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - TextField Style

struct SettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 14))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(AppTheme.paddingStandard)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}
