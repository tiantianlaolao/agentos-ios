import SwiftUI

struct SkillDetailView: View {
    let skill: SkillLibraryItem
    @Bindable var viewModel: SkillsViewModel
    let onInstall: () -> Void
    let onUninstall: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showSecrets: Set<String> = []

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

    private var auditDescription: String {
        switch skill.audit {
        case "platform": return L10n.tr("skillDetail.auditOfficialDesc")
        case "ecosystem": return L10n.tr("skillDetail.auditReviewedDesc")
        default: return L10n.tr("skillDetail.auditUnreviewedDesc")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        heroSection
                        metadataSection
                        permissionsSection
                        functionsSection
                        if skill.installed && !viewModel.configFields.isEmpty {
                            configSection
                        }
                        actionSection
                    }
                    .padding(.horizontal, AppTheme.paddingLarge)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(L10n.tr("skillDetail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("skillDetail.done")) { dismiss() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .task {
            if skill.installed {
                viewModel.requestConfig(skillName: skill.name)
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            Text(skill.emoji ?? "")
                .font(.system(size: 56))

            Text(skill.name)
                .font(AppTheme.titleFont)
                .foregroundStyle(AppTheme.textPrimary)

            Text("v\(skill.version) \(L10n.tr("skills.by")) \(skill.author)")
                .font(AppTheme.captionFont)
                .foregroundStyle(AppTheme.textTertiary)

            Text(skill.description)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            // Audit badge
            HStack(spacing: 6) {
                Image(systemName: skill.audit == "platform" ? "checkmark.shield.fill" : "shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(auditColor)
                Text(auditLabel)
                    .font(AppTheme.captionFont.weight(.semibold))
                    .foregroundStyle(auditColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(auditColor.opacity(0.12))
            .clipShape(Capsule())

            Text(auditDescription)
                .font(AppTheme.smallFont)
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("skillDetail.details"))
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)

            HStack {
                metadataItem(label: L10n.tr("skillDetail.category"), value: skill.category.capitalized)
                Spacer()
                metadataItem(label: L10n.tr("skillDetail.visibility"), value: skill.visibility.capitalized)
                Spacer()
                metadataItem(label: L10n.tr("skillDetail.installs"), value: "\(skill.installCount)")
            }

            if !skill.environments.isEmpty {
                HStack(spacing: 4) {
                    Text(L10n.tr("skillDetail.environments") + ":")
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)
                    ForEach(skill.environments, id: \.self) { env in
                        Text(env)
                            .font(AppTheme.smallFont.weight(.medium))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(AppTheme.smallFont)
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Group {
            if !skill.permissions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("skillDetail.permissions"))
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(skill.permissions, id: \.self) { perm in
                        HStack(spacing: 8) {
                            Image(systemName: permissionIcon(perm))
                                .font(.system(size: 14))
                                .foregroundStyle(isHighRisk(perm) ? AppTheme.warning : AppTheme.textSecondary)
                                .frame(width: 24)
                            Text(perm.capitalized)
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            if isHighRisk(perm) {
                                Text(L10n.tr("skillDetail.highRisk"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppTheme.warning)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.warning.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    // MARK: - Functions

    private var functionsSection: some View {
        Group {
            if !skill.functions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(L10n.tr("skillDetail.functions")) (\(skill.functions.count))")
                        .font(AppTheme.headlineFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(skill.functions) { fn in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fn.name)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.accent)
                            Text(fn.description)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("skillDetail.configuration"))
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(viewModel.configFields) { field in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(field.label)
                            .font(AppTheme.captionFont.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        if field.required == true {
                            Text("*")
                                .foregroundStyle(AppTheme.error)
                        }
                    }

                    if let desc = field.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    if field.secret == true {
                        HStack {
                            if showSecrets.contains(field.key) {
                                TextField("", text: configBinding(for: field.key))
                                    .font(AppTheme.bodyFont)
                                    .foregroundStyle(AppTheme.textPrimary)
                            } else {
                                SecureField("", text: configBinding(for: field.key))
                                    .font(AppTheme.bodyFont)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            Button {
                                if showSecrets.contains(field.key) {
                                    showSecrets.remove(field.key)
                                } else {
                                    showSecrets.insert(field.key)
                                }
                            } label: {
                                Image(systemName: showSecrets.contains(field.key) ? "eye.slash" : "eye")
                                    .foregroundStyle(AppTheme.textTertiary)
                            }
                        }
                        .padding(10)
                        .background(AppTheme.surfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    } else {
                        TextField("", text: configBinding(for: field.key))
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(10)
                            .background(AppTheme.surfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                    }
                }
            }

            Button {
                viewModel.saveConfig(skillName: skill.name)
            } label: {
                Text(viewModel.isConfigSaved ? L10n.tr("skillDetail.savedConfig") : L10n.tr("skillDetail.saveConfiguration"))
                    .font(AppTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.isConfigSaved ? AppTheme.success : AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(spacing: 12) {
            if skill.installed {
                Button {
                    onUninstall()
                    dismiss()
                } label: {
                    Text(L10n.tr("skillDetail.uninstall"))
                        .font(AppTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.error)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            } else {
                Button {
                    onInstall()
                    dismiss()
                } label: {
                    Text(L10n.tr("skillDetail.install"))
                        .font(AppTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }
        }
    }

    // MARK: - Helpers

    private func configBinding(for key: String) -> Binding<String> {
        Binding(
            get: { viewModel.configDraft[key] ?? "" },
            set: { viewModel.configDraft[key] = $0 }
        )
    }

    private func permissionIcon(_ perm: String) -> String {
        switch perm {
        case "network": return "globe"
        case "filesystem": return "folder"
        case "browser": return "safari"
        case "exec": return "terminal"
        case "system": return "gearshape"
        case "contacts": return "person.2"
        case "location": return "location"
        case "camera": return "camera"
        default: return "questionmark.circle"
        }
    }

    private func isHighRisk(_ perm: String) -> Bool {
        ["filesystem", "exec", "system", "browser"].contains(perm)
    }
}
