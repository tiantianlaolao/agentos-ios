import SwiftUI

struct SkillsPanelView: View {
    @Bindable var viewModel: SkillsViewModel
    let wsService: WebSocketService
    var onClose: () -> Void

    @State private var serverUrl = "http://150.109.157.27:3100"
    @State private var authToken = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab selector
                    tabSelector

                    // Search bar
                    searchBar

                    // Category filter (library tab only)
                    if viewModel.activeTab == .library {
                        categoryChips
                    }

                    // Content
                    if viewModel.activeTab == .installed {
                        installedList
                    } else {
                        libraryContent
                    }
                }
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                        .foregroundStyle(AppTheme.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    addSkillMenu
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
            viewModel.setup(wsService: wsService)
            viewModel.requestSkillList()
            viewModel.requestLibrary()
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
                        Text(tab.rawValue)
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
            TextField("Search skills...", text: $viewModel.searchQuery)
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
                    Text("No installed skills")
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Browse the Library to install skills")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredInstalledSkills) { skill in
                            InstalledSkillRow(
                                skill: skill,
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
                            Text("Featured")
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
                        Text(viewModel.selectedCategory == "all" ? "All Skills" : viewModel.selectedCategory.capitalized)
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
                Label("Register HTTP Skill", systemImage: "link")
            }
            Button { viewModel.addSkillMode = .mcp } label: {
                Label("MCP Servers", systemImage: "server.rack")
            }
            Button { viewModel.addSkillMode = .skillmd } label: {
                Label("Import SKILL.md", systemImage: "doc.text")
            }
            Button { viewModel.addSkillMode = .generate } label: {
                Label("AI Generate", systemImage: "sparkles")
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

            Toggle("", isOn: Binding(
                get: { skill.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(AppTheme.primary)
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
                    Text("Installed")
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
        case "platform": return "Official"
        case "ecosystem": return "Reviewed"
        default: return "Unreviewed"
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
                    Text("Installed")
                        .font(AppTheme.smallFont.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                } else {
                    Button {
                        onInstall()
                    } label: {
                        Text("Install")
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
