import SwiftUI

struct SkillStoreView: View {
    @State private var viewModel = SkillStoreViewModel()
    @State private var chatViewModel: ChatViewModel?
    @State private var showAddSkillSheet = false
    @State private var showAddBuiltinMethods = false
    @State private var showAddOpenclawMethods = false
    @State private var addSkillMode: AddSkillMode?
    @State private var addSkillAgentType: String = "builtin"
    @State private var installAgentSheet: SkillLibraryItem?
    @State private var showDesktopRequiredAlert = false

    private enum AddSkillMode: String, Identifiable {
        case http, mcp, skillmd, generate
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Search bar
                        searchBar

                        // Featured section
                        if !viewModel.featured.isEmpty && viewModel.searchText.isEmpty && viewModel.selectedCategory == "all" {
                            featuredSection
                        }

                        // Category chips
                        categoryChips

                        // MCP banner
                        mcpBanner

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
            .confirmationDialog(L10n.tr("skills.selectAgent"), isPresented: Binding(
                get: { installAgentSheet != nil },
                set: { if !$0 { installAgentSheet = nil } }
            )) {
                if let skill = installAgentSheet {
                    let agents = (skill.compatibleAgents ?? ["builtin"]).filter { $0 != "copaw" }
                    if agents.contains("builtin") {
                        Button(L10n.tr("skills.forBuiltinAgent")) {
                            viewModel.installSkill(name: skill.name, agentType: "builtin")
                            installAgentSheet = nil
                        }
                    }
                    if agents.contains("openclaw") {
                        Button(L10n.tr("skills.forOpenclawAgent")) {
                            installAgentSheet = nil
                            showDesktopRequiredAlert = true
                        }
                    }
                    Button(L10n.tr("skills.cancel"), role: .cancel) {
                        installAgentSheet = nil
                    }
                }
            }
            // Step 1: Select agent type for adding skill
            .confirmationDialog(L10n.tr("skills.selectAgentFirst"), isPresented: $showAddSkillSheet) {
                Button(L10n.tr("skills.builtinAgent")) {
                    addSkillAgentType = "builtin"
                    showAddBuiltinMethods = true
                }
                Button(L10n.tr("skills.openclawAgent")) {
                    showDesktopRequiredAlert = true
                }
                Button(L10n.tr("skills.cancel"), role: .cancel) {}
            }
            // Step 2a: Builtin agent methods (4 options)
            .confirmationDialog(L10n.tr("skills.builtinMethods"), isPresented: $showAddBuiltinMethods) {
                Button(L10n.tr("skills.registerHttpSkill")) { addSkillMode = .http }
                Button(L10n.tr("skills.mcpServers")) { addSkillMode = .mcp }
                Button(L10n.tr("skills.importSkillMd")) { addSkillMode = .skillmd }
                Button(L10n.tr("skills.aiGenerate")) { addSkillMode = .generate }
                Button(L10n.tr("skills.cancel"), role: .cancel) {}
            }
            // Step 2b: OpenClaw methods (only SKILL.md)
            .confirmationDialog(L10n.tr("skills.openclawMethods"), isPresented: $showAddOpenclawMethods) {
                Button(L10n.tr("skills.importSkillMd")) { addSkillMode = .skillmd }
                Button(L10n.tr("skills.cancel"), role: .cancel) {}
            }
            .alert(L10n.tr("skills.desktopRequired"), isPresented: $showDesktopRequiredAlert) {
                Button(L10n.tr("skills.ok"), role: .cancel) {}
            } message: {
                Text(L10n.tr("skills.desktopRequiredMessage"))
            }
            .sheet(item: $addSkillMode) { mode in
                switch mode {
                case .http:
                    RegisterSkillView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, onRegistered: { Task { await viewModel.fetchLibrary() } })
                case .mcp:
                    AddMcpServerView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, onAdded: { Task { await viewModel.fetchLibrary() } })
                case .skillmd:
                    ImportSkillMdView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, agentType: addSkillAgentType, onImported: { Task { await viewModel.fetchLibrary() } })
                case .generate:
                    GenerateSkillView(serverUrl: viewModel.serverBaseURL, authToken: viewModel.authToken, onGenerated: { Task { await viewModel.fetchLibrary() } })
                }
            }
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
        // Only skillmd type skills can be installed for OpenClaw
        // Non-skillmd: install directly for builtin without showing agent picker
        let isSkillMd = skill.skillType == "skillmd"

        if !isSkillMd {
            viewModel.installSkill(name: skill.name, agentType: "builtin")
            return
        }

        // For skillmd skills, filter out copaw and show agent picker if multiple agents
        let agents = (skill.compatibleAgents ?? ["builtin"]).filter { $0 != "copaw" }
        if agents.count <= 1 {
            viewModel.installSkill(name: skill.name, agentType: agents.first ?? "builtin")
        } else {
            installAgentSheet = skill
        }
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
                            Text(skill.name)
                                .font(AppTheme.captionFont.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)
                            Text(skill.description)
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

    // MARK: - MCP Banner

    private var mcpBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("skills.mcpBanner"))
                    .font(AppTheme.bodyFont.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(L10n.tr("skills.mcpLearnMore"))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.accent)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(14)
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .padding(.horizontal, AppTheme.paddingLarge)
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
                        Text(skill.name)
                            .font(AppTheme.bodyFont.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        auditBadge(skill.audit)
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
                    Text(skill.description)
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
