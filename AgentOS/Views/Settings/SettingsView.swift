import SwiftUI

struct SettingsView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var viewModel = SettingsViewModel()

    // MARK: - Data

    private let modes: [(key: ConnectionMode, title: String, desc: String, icon: String, color: Color)] = [
        (.builtin, "内置助理", "免费使用", "cpu", Color(hex: "#2d7d46")),                    // L10n: settings.builtin / settings.builtinDesc
        (.openclaw, "OpenClaw", "使用 OpenClaw 智能体，托管或自建", "bolt.fill", Color(hex: "#c26a1b")), // L10n: settings.openclaw / settings.openclawDesc
        (.copaw, "CoPaw", "连接 CoPaw / AgentScope 智能体", "pawprint.fill", Color(hex: "#1b6bc2")),  // L10n: settings.copaw / settings.copawDesc
    ]

    private let models: [(key: String, label: String)] = [
        ("deepseek", "DeepSeek"),
        ("moonshot", "Kimi (Moonshot)"),
        ("anthropic", "Claude (Anthropic)"),
    ]

    private let providers: [(key: LLMProvider, label: String)] = [
        (.deepseek, "DeepSeek"),
        (.openai, "OpenAI"),
        (.anthropic, "Anthropic"),
        (.moonshot, "Kimi"),
    ]

    private let languages: [(key: String, label: String)] = [
        ("zh", "中文"),
        ("en", "English"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Current mode indicator bar
                    currentModeBar
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // Account section
                    accountSection
                        .padding(.bottom, 16)

                    // Connection Mode
                    settingsSection(header: "连接模式") { // L10n: settings.connectionMode
                        connectionModeCards
                    }

                    // Mode-specific configuration
                    modeConfigSection

                    // Language
                    settingsSection(header: "语言") { // L10n: settings.language
                        languageRow
                    }

                    // Save button
                    saveButton
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    // Version
                    versionInfo
                        .padding(.top, 16)

                    // Logout
                    if authViewModel.isLoggedIn {
                        logoutButton
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    } else {
                        Spacer()
                            .frame(height: 32)
                    }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("设置") // L10n: settings.title
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadSettings()
            }
        }
    }

    // MARK: - Current Mode Bar

    private var currentModeBar: some View {
        let modeInfo = modes.first { $0.key == viewModel.mode }
        let modeColor = modeInfo?.color ?? AppTheme.success
        let modeName = modeInfo?.title ?? viewModel.mode.rawValue

        return HStack(spacing: 10) {
            Circle()
                .fill(modeColor)
                .frame(width: 8, height: 8)
            Text("当前连接") // L10n: settings.currentMode
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
            Text(modeName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(modeColor)
            if viewModel.mode == .builtin && viewModel.builtinSubMode == "byok" {
                Text("(自带 Key)") // L10n: settings.builtinByok
                    .font(.system(size: 11))
                    .foregroundStyle(modeColor.opacity(0.8))
            }
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

    private var accountSection: some View {
        Group {
            if authViewModel.isLoggedIn {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已登录") // L10n: settings.loggedInAs
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(authViewModel.phone.isEmpty ? "用户" : authViewModel.phone)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .padding(.horizontal, 16)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("未登录") // L10n: not logged in
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("匿名模式，部分功能受限") // L10n: anonymous mode
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.surface)
                .padding(.horizontal, 16)
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
                            Text(m.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(m.desc)
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
            settingsSection(header: "模式") { // L10n: mode
                VStack(spacing: 0) {
                    subModeRow(
                        title: "免费额度", // L10n: settings.builtinFree
                        subtitle: "免费使用", // L10n: settings.builtinDesc
                        selected: viewModel.builtinSubMode == "free",
                        isLast: false
                    ) {
                        viewModel.builtinSubMode = "free"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: "自带 Key", // L10n: settings.builtinByok
                        subtitle: "使用自己的 API Key，无限制", // L10n: settings.byokDesc
                        selected: viewModel.builtinSubMode == "byok",
                        isLast: true
                    ) {
                        viewModel.builtinSubMode = "byok"
                    }
                }
            }

            if viewModel.builtinSubMode == "free" {
                // Model dropdown
                settingsSection(header: "模型选择") { // L10n: settings.model
                    dropdownRow(
                        icon: "brain",
                        label: "模型", // L10n: settings.model
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
        settingsSection(header: "AI 服务商配置") { // L10n: settings.provider
            VStack(spacing: 0) {
                // Provider dropdown
                dropdownRow(
                    icon: "server.rack",
                    label: "AI 服务商", // L10n: settings.provider
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
                    Text("API Key") // L10n: settings.apiKey
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    SecureField("输入你的 API Key", text: $viewModel.apiKey) // L10n: settings.apiKeyPlaceholder
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

    // MARK: - OpenClaw Config

    private var openclawConfig: some View {
        VStack(spacing: 0) {
            // Sub-mode: Hosted vs Self-hosted
            settingsSection(header: "部署模式") { // L10n: deploy mode
                VStack(spacing: 0) {
                    subModeRow(
                        title: "托管模式", // L10n: settings.openclawHosted
                        subtitle: "平台提供，免费试用 50 条", // L10n: settings.openclawHostedDesc
                        selected: viewModel.openclawSubMode == "hosted",
                        isLast: false
                    ) {
                        viewModel.openclawSubMode = "hosted"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: "自建直连", // L10n: settings.openclawSelfhosted
                        subtitle: "连接你自己的 Gateway", // L10n: settings.openclawSelfhostedDesc
                        selected: viewModel.openclawSubMode == "selfhosted",
                        isLast: true
                    ) {
                        viewModel.openclawSubMode = "selfhosted"
                    }
                }
            }

            if viewModel.openclawSubMode == "hosted" {
                // Hosted: Invitation code + Quota (THIS IS WHERE HOSTED GOES)
                if authViewModel.isLoggedIn {
                    hostedSection
                } else {
                    settingsSection(header: "托管服务") { // L10n: hosted service
                        HStack(spacing: 12) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 24)
                            Text("请先登录以使用托管模式") // L10n: settings.hostedLoginRequired
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            } else {
                // Self-hosted: Gateway URL + Token
                settingsSection(header: "Gateway 配置") { // L10n: gateway config
                    VStack(spacing: 0) {
                        textFieldRow(
                            icon: "link",
                            label: "Gateway 地址", // L10n: settings.openclawUrl
                            placeholder: "ws://你的公网IP:18789", // L10n: settings.openclawUrlPlaceholder
                            text: $viewModel.openclawUrl,
                            isSecure: false
                        )
                        Divider().background(AppTheme.divider).padding(.leading, 52)
                        textFieldRow(
                            icon: "lock.fill",
                            label: "Token", // L10n: settings.openclawToken
                            placeholder: "输入 Gateway 认证 Token", // L10n: settings.openclawTokenPlaceholder
                            text: $viewModel.openclawToken,
                            isSecure: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - CoPaw Config

    private var copawConfig: some View {
        VStack(spacing: 0) {
            // Sub-mode
            settingsSection(header: "部署模式") { // L10n: deploy mode
                VStack(spacing: 0) {
                    subModeRow(
                        title: "托管模式", // L10n: settings.copawHosted
                        subtitle: "使用平台提供的 CoPaw 服务，无需配置", // L10n: settings.copawHostedDesc
                        selected: viewModel.copawSubMode == "hosted",
                        isLast: false
                    ) {
                        viewModel.copawSubMode = "hosted"
                    }
                    Divider().background(AppTheme.divider).padding(.leading, 52)
                    subModeRow(
                        title: "自建直连", // L10n: settings.copawSelfhosted
                        subtitle: "连接你自己的 CoPaw / AgentScope 实例", // L10n: settings.copawSelfhostedDesc
                        selected: viewModel.copawSubMode == "selfhosted",
                        isLast: true
                    ) {
                        viewModel.copawSubMode = "selfhosted"
                    }
                }
            }

            if viewModel.copawSubMode == "selfhosted" {
                settingsSection(header: "CoPaw 配置") { // L10n: copaw config
                    VStack(spacing: 0) {
                        textFieldRow(
                            icon: "link",
                            label: "CoPaw 地址", // L10n: settings.copawUrl
                            placeholder: "http://你的IP:8088", // L10n: settings.copawUrlPlaceholder
                            text: $viewModel.copawUrl,
                            isSecure: false
                        )
                        Divider().background(AppTheme.divider).padding(.leading, 52)
                        textFieldRow(
                            icon: "lock.fill",
                            label: "Token", // L10n: settings.copawToken
                            placeholder: "输入认证 Token（可选）", // L10n: settings.copawTokenPlaceholder
                            text: $viewModel.copawToken,
                            isSecure: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - Hosted Section (OpenClaw > Hosted)

    private var hostedSection: some View {
        settingsSection(header: "托管服务") { // L10n: hosted service
            if viewModel.hostedActivated {
                VStack(spacing: 8) {
                    // Status row
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.success)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已激活") // L10n: activated
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.success)

                            if viewModel.hostedInstanceStatus == "provisioning" {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(AppTheme.warning)
                                    Text("实例启动中...") // L10n: settings.hostedProvisioning
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.warning)
                                }
                            } else if viewModel.hostedInstanceStatus == "error" {
                                Text("实例启动失败，请联系管理员") // L10n: settings.hostedError
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.error)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Quota bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("试用额度") // L10n: quota
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textTertiary)
                            Spacer()
                            Text("\(viewModel.hostedQuotaUsed) / \(viewModel.hostedQuotaTotal)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AppTheme.surfaceLight)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(quotaColor)
                                    .frame(width: max(0, geo.size.width * quotaProgress))
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textTertiary)
                            .frame(width: 24)
                        Text("输入邀请码激活托管服务") // L10n: enter invitation code
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    HStack(spacing: 10) {
                        TextField("AOS-XXXXX", text: $viewModel.invitationCode)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(AppTheme.surfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .autocapitalization(.allCharacters)
                            .autocorrectionDisabled()

                        Button {
                            Task { await viewModel.activateInvitationCode() }
                        } label: {
                            Group {
                                if viewModel.isActivating {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                } else {
                                    Text("激活") // L10n: settings.hostedActivate
                                        .font(.system(size: 14, weight: .medium))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                viewModel.invitationCode.trimmed.isEmpty || viewModel.isActivating
                                    ? AppTheme.primary.opacity(0.4)
                                    : AppTheme.primary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(viewModel.invitationCode.trimmed.isEmpty || viewModel.isActivating)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var quotaProgress: CGFloat {
        guard viewModel.hostedQuotaTotal > 0 else { return 0 }
        return min(1, CGFloat(viewModel.hostedQuotaUsed) / CGFloat(viewModel.hostedQuotaTotal))
    }

    private var quotaColor: Color {
        quotaProgress > 0.9 ? AppTheme.error : quotaProgress > 0.7 ? AppTheme.warning : AppTheme.success
    }

    // MARK: - Language Row (Dropdown)

    private var languageRow: some View {
        dropdownRow(
            icon: "globe",
            label: "语言", // L10n: settings.language
            options: languages,
            selected: viewModel.locale
        ) {
            viewModel.locale = $0
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
                    Text("已保存") // L10n: settings.saved
                } else {
                    Text("保存") // L10n: settings.save
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

    // MARK: - Version

    private var versionInfo: some View {
        Text("AgentOS iOS v1.0.0") // L10n: settings.version
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            Task { await authViewModel.logout() }
        } label: {
            Text("退出登录") // L10n: settings.logout
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

    // MARK: - Reusable Components

    /// Section container with optional header — Telegram-style grouped card
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

    /// Sub-mode radio row (hosted/selfhosted, free/byok)
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

    /// Dropdown row using Menu — native iOS popover
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

// MARK: - TextField Style (kept for backward compat)

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
