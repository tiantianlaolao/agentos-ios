import SwiftUI

struct SettingsView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var viewModel = SettingsViewModel()

    private let modes: [(key: ConnectionMode, title: String, desc: String, color: Color)] = [
        (.builtin, "Built-in Agent", "Zero config, powered by DeepSeek", Color(hex: "#2d7d46")),
        (.openclaw, "OpenClaw", "Connect to OpenClaw Agent", Color(hex: "#c26a1b")),
        (.copaw, "CoPaw", "Connect to CoPaw Agent", Color(hex: "#1b6bc2")),
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
                VStack(alignment: .leading, spacing: AppTheme.paddingLarge) {
                    // Current mode indicator
                    currentModeBar

                    // Account info
                    accountSection

                    // Connection Mode
                    sectionHeader("Connection Mode")
                    connectionModeSection

                    // Mode-specific config
                    modeConfigSection

                    // Language
                    sectionHeader("Language")
                    languageSection

                    // Save button
                    saveButton

                    // Version
                    versionInfo

                    // Logout
                    if authViewModel.isLoggedIn {
                        logoutButton
                    }
                }
                .padding(AppTheme.paddingLarge)
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Settings"))
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
        return HStack(spacing: 8) {
            Circle()
                .fill(modeColor)
                .frame(width: 8, height: 8)
            Text("Current:")
                .font(AppTheme.captionFont)
                .foregroundStyle(AppTheme.textSecondary)
            Text(modeInfo?.title ?? viewModel.mode.rawValue)
                .font(AppTheme.captionFont)
                .foregroundStyle(modeColor)
            if viewModel.mode == .builtin && viewModel.builtinSubMode == "byok" {
                Text("(BYOK)")
                    .font(AppTheme.smallFont)
                    .foregroundStyle(modeColor)
            }
            Spacer()
        }
        .padding(AppTheme.paddingStandard)
        .background(modeColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .stroke(modeColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Account

    private var accountSection: some View {
        Group {
            if authViewModel.isLoggedIn {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(AppTheme.primary)
                    Text(authViewModel.phone)
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                }
                .padding(AppTheme.paddingStandard)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            } else {
                Text("Not logged in (anonymous mode)")
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
    }

    // MARK: - Connection Mode

    private var connectionModeSection: some View {
        VStack(spacing: 8) {
            ForEach(modes, id: \.key) { m in
                Button {
                    viewModel.mode = m.key
                } label: {
                    HStack {
                        Circle()
                            .fill(m.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title)
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(m.desc)
                                .font(AppTheme.smallFont)
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        Spacer()
                        if viewModel.mode == m.key {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.primary)
                        }
                    }
                    .padding(AppTheme.paddingStandard)
                    .background(viewModel.mode == m.key ? AppTheme.primary.opacity(0.1) : AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                            .stroke(viewModel.mode == m.key ? AppTheme.primary.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Mode Config

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

    private var builtinConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sub mode: free vs byok
            sectionHeader("Mode")
            HStack(spacing: 8) {
                subModeButton(title: "Free", selected: viewModel.builtinSubMode == "free") {
                    viewModel.builtinSubMode = "free"
                }
                subModeButton(title: "BYOK", selected: viewModel.builtinSubMode == "byok") {
                    viewModel.builtinSubMode = "byok"
                }
            }

            if viewModel.builtinSubMode == "free" {
                // Model selection
                sectionHeader("Model")
                settingsPicker(options: models, selected: viewModel.selectedModel) { viewModel.selectedModel = $0 }

                // Hosted mode
                if authViewModel.isLoggedIn {
                    hostedSection
                }
            } else {
                byokConfig
            }
        }
    }

    private var byokConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Provider")
            settingsPicker(options: providers.map { (key: $0.key.rawValue, label: $0.label) }, selected: viewModel.provider.rawValue) {
                viewModel.provider = LLMProvider(rawValue: $0) ?? .deepseek
            }

            sectionHeader("API Key")
            SecureField("Enter API Key", text: $viewModel.apiKey)
                .textFieldStyle(SettingsTextFieldStyle())
        }
    }

    private var openclawConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sub mode
            sectionHeader("Deploy Mode")
            HStack(spacing: 8) {
                subModeButton(title: "Hosted", selected: viewModel.openclawSubMode == "hosted") {
                    viewModel.openclawSubMode = "hosted"
                }
                subModeButton(title: "Self-hosted", selected: viewModel.openclawSubMode == "selfhosted") {
                    viewModel.openclawSubMode = "selfhosted"
                }
            }

            if viewModel.openclawSubMode == "selfhosted" {
                sectionHeader("Gateway URL")
                TextField("ws://your-server:port", text: $viewModel.openclawUrl)
                    .textFieldStyle(SettingsTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                sectionHeader("Token")
                SecureField("Access token", text: $viewModel.openclawToken)
                    .textFieldStyle(SettingsTextFieldStyle())
            }
        }
    }

    private var copawConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                subModeButton(title: "Hosted", selected: viewModel.copawSubMode == "hosted") {
                    viewModel.copawSubMode = "hosted"
                }
                subModeButton(title: "Self-hosted", selected: viewModel.copawSubMode == "selfhosted") {
                    viewModel.copawSubMode = "selfhosted"
                }
            }

            if viewModel.copawSubMode == "selfhosted" {
                sectionHeader("CoPaw URL")
                TextField("http://your-server:8088", text: $viewModel.copawUrl)
                    .textFieldStyle(SettingsTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                sectionHeader("Token")
                SecureField("Access token", text: $viewModel.copawToken)
                    .textFieldStyle(SettingsTextFieldStyle())
            }
        }
    }

    // MARK: - Hosted

    private var hostedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Hosted OpenClaw")

            if viewModel.hostedActivated {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text("Activated")
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.success)
                    }

                    if viewModel.hostedInstanceStatus == "provisioning" {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Instance provisioning...")
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.warning)
                        }
                    }

                    Text("Quota: \(viewModel.hostedQuotaUsed) / \(viewModel.hostedQuotaTotal)")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)

                    // Quota progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.surfaceLight)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(quotaColor)
                                .frame(width: geo.size.width * quotaProgress)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(AppTheme.paddingStandard)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter invitation code to activate")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack {
                        TextField("AOS-XXXXX", text: $viewModel.invitationCode)
                            .textFieldStyle(SettingsTextFieldStyle())
                            .autocapitalization(.allCharacters)
                        Button {
                            Task { await viewModel.activateInvitationCode() }
                        } label: {
                            if viewModel.isActivating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Activate")
                            }
                        }
                        .font(AppTheme.captionFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                        .disabled(viewModel.invitationCode.trimmed.isEmpty || viewModel.isActivating)
                    }
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

    // MARK: - Language

    private var languageSection: some View {
        settingsPicker(options: languages, selected: viewModel.locale) { viewModel.locale = $0 }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            Task { await viewModel.saveSettings() }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.showSaved {
                    Image(systemName: "checkmark")
                    Text("Saved!")
                } else {
                    Text("Save Settings")
                }
            }
            .font(AppTheme.headlineFont)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.paddingStandard)
            .background(viewModel.showSaved ? AppTheme.success : AppTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .disabled(viewModel.isSaving)
    }

    // MARK: - Version

    private var versionInfo: some View {
        HStack {
            Spacer()
            Text("AgentOS iOS v1.0.0")
                .font(AppTheme.smallFont)
                .foregroundStyle(AppTheme.textTertiary)
            Spacer()
        }
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button {
            Task { await authViewModel.logout() }
        } label: {
            Text("Logout")
                .font(AppTheme.headlineFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.paddingStandard)
                .background(AppTheme.error)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .padding(.bottom, AppTheme.paddingXLarge)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTheme.captionFont)
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }

    private func subModeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.captionFont)
                .foregroundStyle(selected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selected ? AppTheme.primary : AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        }
    }

    private func settingsPicker(options: [(key: String, label: String)], selected: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(spacing: 4) {
            ForEach(options, id: \.key) { opt in
                Button {
                    onChange(opt.key)
                } label: {
                    HStack {
                        Text(opt.label)
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        if selected == opt.key {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.primary)
                        }
                    }
                    .padding(AppTheme.paddingStandard)
                    .background(selected == opt.key ? AppTheme.primary.opacity(0.1) : AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                }
            }
        }
    }
}

// MARK: - TextField Style

struct SettingsTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(AppTheme.bodyFont)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(AppTheme.paddingStandard)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}
