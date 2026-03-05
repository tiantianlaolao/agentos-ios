import SwiftUI

struct SkillStoreView: View {
    @State private var viewModel = SkillStoreViewModel()
    @State private var chatViewModel: ChatViewModel?

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
            }
            .navigationTitle(L10n.tr("skills.store"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.fetchFeatured()
            await viewModel.fetchStats()
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

            if skill.installed {
                Text(L10n.tr("skills.installedBadge"))
                    .font(AppTheme.smallFont.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
            } else {
                Button {
                    viewModel.installSkill(name: skill.name)
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
