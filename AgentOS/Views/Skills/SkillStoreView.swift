import SwiftUI

struct SkillStoreView: View {
    @State private var viewModel = SkillStoreViewModel()
    @State private var chatViewModel: ChatViewModel?
    @State private var showAddSkillSheet = false
    @State private var addSkillMode: AddSkillMode?
    @State private var addSkillAgentType: String = "builtin"
    @State private var showBacktestWorkstation = false

    private enum AddSkillMode: String, Identifiable {
        case http, skillmd, generate
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Pro Workstation section
                        if viewModel.searchText.isEmpty && viewModel.selectedCategory == "all" {
                            proWorkstationSection
                        }

                        // Search bar
                        searchBar

                        // Featured section
                        if !viewModel.featured.isEmpty && viewModel.searchText.isEmpty && viewModel.selectedCategory == "all" {
                            featuredSection
                        }

                        // Category chips
                        categoryChips

                        // Skill list
                        skillList
                    }
                    .padding(.vertical, 8)
                }

                // Floating add skill button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showAddSkillSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(AppTheme.primary)
                                .clipShape(Circle())
                                .shadow(color: AppTheme.primary.opacity(0.3), radius: 8, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(L10n.tr("skills.store"))
            .navigationBarTitleDisplayMode(.inline)
            // External Agent picker retired 2026-04-19 — skills always install to builtin
            // Skill add methods menu (simplified: no agent picker)
            .confirmationDialog(L10n.tr("skills.builtinMethods"), isPresented: $showAddSkillSheet) {
                Button(L10n.tr("skills.registerHttpSkill")) { addSkillMode = .http }
                Button(L10n.tr("skills.importSkillMd")) { addSkillMode = .skillmd }
                Button(L10n.tr("skills.aiGenerate")) { addSkillMode = .generate }
                Button(L10n.tr("skills.cancel"), role: .cancel) {}
            }
            .sheet(item: $addSkillMode) { mode in
                switch mode {
                case .http:
                    RegisterSkillView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, onRegistered: { Task { await viewModel.fetchLibrary() } })
                case .skillmd:
                    ImportSkillMdView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, agentType: addSkillAgentType, onImported: { Task { await viewModel.fetchLibrary() } })
                case .generate:
                    GenerateSkillView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, onGenerated: { Task { await viewModel.fetchLibrary() } })
                }
            }
        }
        .fullScreenCover(isPresented: $showBacktestWorkstation) {
            BacktestWorkstationView()
        }
        .task {
            // Load server URL and token from settings
            let url = (try? await DatabaseService.shared.getSetting(key: "serverUrl")) ?? ServerConfig.shared.httpBaseURL
            let token = (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? ""
            viewModel.setup(serverUrl: url, authToken: token)
            await viewModel.fetchFeatured()
            await viewModel.fetchStats()
            await viewModel.fetchLibrary()
        }
    }

    private func agentLabel(_ agent: String) -> String {
        switch agent {
        case "builtin": return L10n.tr("skills.builtinAgent")
        case "openclaw": return L10n.tr("skills.openclawAgent")
        default: return agent
        }
    }

    private func handleInstall(_ skill: SkillLibraryItem) {
        // External Agent retired 2026-04-19 — always install to builtin
        viewModel.installSkill(name: skill.name, agentType: "builtin")
    }

    private func handleUninstall(_ skill: SkillLibraryItem) {
        // Find which agents have this skill installed
        let installedAgentNames = (skill.installedAgents ?? [:])
            .filter { $0.value && $0.key != "copaw" }
            .map(\.key)

        if installedAgentNames.isEmpty {
            // Fallback: uninstall for builtin
            viewModel.uninstallSkill(name: skill.name, agentType: "builtin")
        } else if installedAgentNames.count == 1 {
            viewModel.uninstallSkill(name: skill.name, agentType: installedAgentNames[0])
        } else {
            // Multiple agents — uninstall all (could show picker but keep simple for now)
            for agent in installedAgentNames {
                viewModel.uninstallSkill(name: skill.name, agentType: agent)
            }
        }
    }

    // MARK: - Pro Workstation

    private var proWorkstationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("专业工作台")
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.paddingLarge)

            Button {
                showBacktestWorkstation = true
            } label: {
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("📈")
                            .font(.system(size: 36))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("回测助手")
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("13种策略 · 5000+只A股 · AI对话式分析")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textSecondary)
                        Text("K线图 · 基本面画像 · 因子选股 · 策略回测")
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.primary.opacity(0.08), AppTheme.primary.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.primary.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.paddingLarge)

            // Placeholder for future workstations
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 14))
                Text("更多专业工具即将上线")
                    .font(AppTheme.captionFont)
            }
            .foregroundStyle(AppTheme.textTertiary)
            .padding(.horizontal, AppTheme.paddingLarge)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textTertiary)
            TextField(L10n.tr("skills.searchPlaceholder"), text: $viewModel.searchText)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }
        }
        .padding(10)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .padding(.horizontal, AppTheme.paddingLarge)
    }

    // MARK: - Featured

    private var lang: String { L10n.shared.locale }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("skills.featured"))
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.paddingLarge)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.featured) { skill in
                        VStack(spacing: 8) {
                            Text(skill.emoji ?? "")
                                .font(.system(size: 32))
                            HStack(spacing: 4) {
                                Text(skill.localizedName(language: lang))
                                    .font(AppTheme.captionFont.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                if skill.name == "proactive" || skill.name == "public-link" {
                                    Text("会员")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(AppTheme.primary)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(skill.localizedDescription(language: lang))
                                .font(AppTheme.smallFont)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 10))
                                Text(L10n.tr("skills.installCount", ["count": "\(skill.installCount)"]))
                                    .font(AppTheme.smallFont)
                            }
                            .foregroundStyle(AppTheme.textTertiary)

                            auditBadge(skill.audit)
                        }
                        .frame(width: 140)
                        .padding(12)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    }
                }
                .padding(.horizontal, AppTheme.paddingLarge)
            }
        }
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(key: "all", label: L10n.tr("skills.all"))
                ForEach(viewModel.categories, id: \.self) { cat in
                    categoryChip(key: cat, label: cat.capitalized)
                }
            }
            .padding(.horizontal, AppTheme.paddingLarge)
        }
    }

    private func categoryChip(key: String, label: String) -> some View {
        Button {
            viewModel.selectedCategory = key
        } label: {
            Text(label)
                .font(AppTheme.captionFont.weight(.medium))
                .foregroundStyle(viewModel.selectedCategory == key ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(viewModel.selectedCategory == key ? AppTheme.primary : AppTheme.surfaceLight)
                .clipShape(Capsule())
        }
    }

    // MARK: - Skill List

    private var skillList: some View {
        LazyVStack(spacing: 8) {
            if viewModel.filteredSkills.isEmpty && !viewModel.searchText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(L10n.tr("skills.noResults"))
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ForEach(viewModel.filteredSkills) { skill in
                    skillRow(skill)
                }
            }
        }
        .padding(.horizontal, AppTheme.paddingLarge)
    }

    private func skillRow(_ skill: SkillLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(skill.emoji ?? "")
                    .font(.system(size: 28))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(skill.localizedName(language: lang))
                            .font(AppTheme.bodyFont.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        auditBadge(skill.audit)
                        if skill.name == "proactive" || skill.name == "public-link" {
                            Text("会员专属")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppTheme.primary)
                                .clipShape(Capsule())
                        }
                        if let skillType = skill.skillType {
                            Text(skillType == "system" ? L10n.tr("skills.systemSkill") : L10n.tr("skills.knowledgeSkill"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(skillType == "system" ? AppTheme.primary : AppTheme.warning)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background((skillType == "system" ? AppTheme.primary : AppTheme.warning).opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(skill.localizedDescription(language: lang))
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if skill.installCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 10))
                                Text(L10n.tr("skills.installCount", ["count": "\(skill.installCount)"]))
                                    .font(AppTheme.smallFont)
                            }
                            .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 4) {
                    if skill.visibility == "private" {
                        Button {
                            // Apply publish action placeholder
                        } label: {
                            Text(L10n.tr("skills.applyPublish"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(
                                    Capsule().stroke(AppTheme.warning, lineWidth: 1)
                                )
                        }
                    }
                    if skill.installed {
                        VStack(spacing: 4) {
                            Button {
                                handleUninstall(skill)
                            } label: {
                                Text(L10n.tr("skills.uninstall"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.error)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        Capsule().stroke(AppTheme.error, lineWidth: 1)
                                    )
                            }
                            Text(L10n.tr("skills.installedBadge"))
                                .font(AppTheme.smallFont.weight(.semibold))
                                .foregroundStyle(AppTheme.success)
                        }
                    } else {
                        Button {
                            handleInstall(skill)
                        } label: {
                            Text(L10n.tr("skills.install"))
                                .font(AppTheme.captionFont.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Compatible agents row (filter out copaw)
            if let agents = skill.compatibleAgents?.filter({ $0 != "copaw" }), !agents.isEmpty {
                HStack(spacing: 4) {
                    Text(L10n.tr("skills.compatibleWith") + ":")
                        .font(AppTheme.smallFont)
                        .foregroundStyle(AppTheme.textTertiary)
                    ForEach(agents, id: \.self) { agent in
                        Text(agentLabel(agent))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.surfaceLight)
                            .clipShape(Capsule())
                    }
                }
                .padding(.leading, 52)
            }

            // Installed agents row (filter out copaw)
            if let installedAgents = skill.installedAgents {
                let activeAgents = installedAgents.filter { $0.value && $0.key != "copaw" }.map(\.key)
                if !activeAgents.isEmpty {
                    HStack(spacing: 4) {
                        Text(L10n.tr("skills.installedFor") + ":")
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)
                        ForEach(activeAgents, id: \.self) { agent in
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                Text(agentLabel(agent))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.success.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.leading, 52)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Helpers

    private func auditBadge(_ audit: String) -> some View {
        let color: Color = {
            switch audit {
            case "platform": return AppTheme.success
            case "ecosystem": return AppTheme.warning
            default: return AppTheme.textTertiary
            }
        }()
        let label: String = {
            switch audit {
            case "platform": return L10n.tr("skillDetail.auditOfficial")
            case "ecosystem": return L10n.tr("skillDetail.auditReviewed")
            default: return L10n.tr("skillDetail.auditUnreviewed")
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
