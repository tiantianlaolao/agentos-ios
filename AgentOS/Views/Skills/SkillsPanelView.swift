import SwiftUI

struct SkillsPanelView: View {
    @Bindable var viewModel: SkillsViewModel
    let wsService: WebSocketService
    let mode: ConnectionMode
    var onClose: () -> Void

    @State private var serverUrl = "http://43.154.188.177:3100"
    @State private var authToken = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab selector (only show if mode has library)
                    if viewModel.hasLibrary {
                        tabSelector
                    }

                    // Search bar
                    searchBar

                    // Category filter (library tab only)
                    if viewModel.activeTab == .library && viewModel.hasLibrary {
                        categoryChips
                    }

                    // Content
                    if viewModel.activeTab == .installed || !viewModel.hasLibrary {
                        installedList
                    } else {
                        libraryContent
                    }
                }
            }
            .navigationTitle(L10n.tr("skills.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("skills.done")) { onClose() }
                        .foregroundStyle(AppTheme.primary)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    // Refresh button
                    Button {
                        viewModel.refreshSkills()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppTheme.primary)
                    }
                    // Add skill menu (only for modes with library)
                    if viewModel.hasLibrary {
                        addSkillMenu
                    }
                }
            }
            .sheet(item: $viewModel.selectedLibrarySkill) { skill in
                SkillDetailView(
                    skill: skill,
                    viewModel: viewModel,
                    onInstall: { viewModel.installSkill(name: skill.name) },
                    onUninstall: { viewModel.uninstallSkill(name: skill.name) }
                )
            }
            .sheet(item: $viewModel.addSkillMode) { mode in
                switch mode {
                case .http:
                    RegisterSkillView(
                        serverUrl: serverUrl,
                        authToken: authToken,
                        onRegistered: { viewModel.requestSkillList(); viewModel.requestLibrary() }
                    )
                case .mcp:
                    AddMcpServerView(
                        serverUrl: serverUrl,
                        authToken: authToken,
                        onAdded: { viewModel.requestSkillList() }
                    )
                case .skillmd:
                    ImportSkillMdView(
                        serverUrl: serverUrl,
                        authToken: authToken,
                        onImported: { viewModel.requestSkillList(); viewModel.requestLibrary() }
                    )
                case .generate:
                    GenerateSkillView(
                        serverUrl: serverUrl,
                        authToken: authToken,
                        onGenerated: { viewModel.requestSkillList(); viewModel.requestLibrary() }
                    )
                }
            }
        }
        .task {
            authToken = (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? ""
            let userId = (try? await DatabaseService.shared.getSetting(key: "auth_userId")) ?? ""
            let ukey = userId.isEmpty ? "openclawSubMode" : "\(userId):openclawSubMode"
            let subMode = (try? await DatabaseService.shared.getSetting(key: ukey)) ?? "hosted"
            viewModel.currentMode = mode
            viewModel.openclawSubMode = subMode
            viewModel.setup(wsService: wsService)
            viewModel.refreshSkills()
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SkillsViewModel.SkillsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.activeTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab == .installed ? L10n.tr("skills.installed") : L10n.tr("skills.library"))
                            .font(AppTheme.bodyFont.weight(viewModel.activeTab == tab ? .semibold : .regular))
                            .foregroundStyle(viewModel.activeTab == tab ? AppTheme.primary : AppTheme.textSecondary)

                        Rectangle()
                            .fill(viewModel.activeTab == tab ? AppTheme.primary : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppTheme.paddingLarge)
        .padding(.top, 4)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textTertiary)
            TextField(L10n.tr("skills.searchPlaceholder"), text: $viewModel.searchQuery)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
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
        .padding(.vertical, 8)
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(skillCategories) { cat in
                    Button {
                        viewModel.selectedCategory = cat.key
                    } label: {
                        Text(cat.label)
                            .font(AppTheme.captionFont.weight(.medium))
                            .foregroundStyle(viewModel.selectedCategory == cat.key ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.selectedCategory == cat.key
                                    ? AppTheme.primary
                                    : AppTheme.surfaceLight
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, AppTheme.paddingLarge)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Installed List

    private var installedList: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.primary)
                    Spacer()
                }
            } else if viewModel.filteredInstalledSkills.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(L10n.tr("skills.noInstalledSkills"))
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    if viewModel.hasLibrary {
                        Text(L10n.tr("skills.browseLibraryHint"))
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredInstalledSkills) { skill in
                            InstalledSkillRow(
                                skill: skill,
                                canToggle: viewModel.canToggleSkills,
                                onToggle: { enabled in
                                    viewModel.toggleSkill(name: skill.name, enabled: enabled)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.paddingLarge)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        Group {
            if viewModel.isLibraryLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(AppTheme.primary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Featured section
                        if !viewModel.featuredSkills.isEmpty && viewModel.selectedCategory == "all" && viewModel.searchQuery.isEmpty {
                            Text(L10n.tr("skills.featured"))
                                .font(AppTheme.headlineFont)
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, AppTheme.paddingLarge)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(viewModel.featuredSkills) { skill in
                                        FeaturedSkillCard(skill: skill) {
                                            viewModel.selectedLibrarySkill = skill
                                        }
                                    }
                                }
                                .padding(.horizontal, AppTheme.paddingLarge)
                            }
                            .padding(.bottom, 8)
                        }

                        // All library skills
                        Text(viewModel.selectedCategory == "all" ? L10n.tr("skills.allSkills") : viewModel.selectedCategory.capitalized)
                            .font(AppTheme.headlineFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, AppTheme.paddingLarge)

                        ForEach(viewModel.filteredLibrarySkills) { skill in
                            LibrarySkillRow(skill: skill) {
                                viewModel.selectedLibrarySkill = skill
                            } onInstall: {
                                viewModel.installSkill(name: skill.name)
                            }
                            .padding(.horizontal, AppTheme.paddingLarge)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    // MARK: - Add Skill Menu

    private var addSkillMenu: some View {
        Menu {
            Button { viewModel.addSkillMode = .http } label: {
                Label(L10n.tr("skills.registerHttpSkill"), systemImage: "link")
            }
            Button { viewModel.addSkillMode = .mcp } label: {
                Label(L10n.tr("skills.mcpServers"), systemImage: "server.rack")
            }
            Button { viewModel.addSkillMode = .skillmd } label: {
                Label(L10n.tr("skills.importSkillMd"), systemImage: "doc.text")
            }
            Button { viewModel.addSkillMode = .generate } label: {
                Label(L10n.tr("skills.aiGenerate"), systemImage: "sparkles")
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(AppTheme.primary)
        }
    }
}

// MARK: - Installed Skill Row

private struct InstalledSkillRow: View {
    let skill: SkillManifestInfo
    let canToggle: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(skill.emoji ?? "")
                .font(.system(size: 28))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(AppTheme.bodyFont.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(skill.description)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canToggle {
                Toggle("", isOn: Binding(
                    get: { skill.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .tint(AppTheme.primary)
            } else {
                // Read-only status indicator
                Circle()
                    .fill(skill.enabled ? AppTheme.success : AppTheme.textTertiary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

// MARK: - Featured Skill Card

private struct FeaturedSkillCard: View {
    let skill: SkillLibraryItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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

                if skill.installed {
                    Text(L10n.tr("skills.installedBadge"))
                        .font(AppTheme.smallFont.weight(.medium))
                        .foregroundStyle(AppTheme.success)
                }
            }
            .frame(width: 130)
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }
}

// MARK: - Library Skill Row

private struct LibrarySkillRow: View {
    let skill: SkillLibraryItem
    let onTap: () -> Void
    let onInstall: () -> Void

    private var auditColor: Color {
        switch skill.audit {
        case "platform": return AppTheme.success
        case "ecosystem": return AppTheme.warning
        default: return AppTheme.textTertiary
        }
    }

    private var auditLabel: String {
        switch skill.audit {
        case "platform": return L10n.tr("skillDetail.auditOfficial")
        case "ecosystem": return L10n.tr("skillDetail.auditReviewed")
        default: return L10n.tr("skillDetail.auditUnreviewed")
        }
    }

    var body: some View {
        Button(action: onTap) {
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

                        Text(auditLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(auditColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(auditColor.opacity(0.15))
                            .clipShape(Capsule())
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
                                Text("\(skill.installCount)")
                                    .font(AppTheme.smallFont)
                            }
                            .foregroundStyle(AppTheme.textTertiary)
                        }
                        Text("v\(skill.version)")
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if skill.installed {
                    Text(L10n.tr("skills.installedBadge"))
                        .font(AppTheme.smallFont.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                } else {
                    Button {
                        onInstall()
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
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .buttonStyle(.plain)
    }
}
