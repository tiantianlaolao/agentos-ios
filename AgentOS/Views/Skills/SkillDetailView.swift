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
        case "platform": return "Official"
        case "ecosystem": return "Reviewed"
        default: return "Unreviewed"
        }
    }

    private var auditDescription: String {
        switch skill.audit {
        case "platform": return "Developed and maintained by the AgentOS team"
        case "ecosystem": return "Reviewed by the ecosystem maintainers"
        default: return "Not yet reviewed - use with caution"
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
            .navigationTitle("Skill Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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

            Text("v\(skill.version) by \(skill.author)")
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
            Text("Details")
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)

            HStack {
                metadataItem(label: "Category", value: skill.category.capitalized)
                Spacer()
                metadataItem(label: "Visibility", value: skill.visibility.capitalized)
                Spacer()
                metadataItem(label: "Installs", value: "\(skill.installCount)")
            }

            if !skill.environments.isEmpty {
                HStack(spacing: 4) {
                    Text("Environments:")
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
                    Text("Permissions")
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
                                Text("High Risk")
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
                    Text("Functions (\(skill.functions.count))")
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
            Text("Configuration")
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
                Text(viewModel.isConfigSaved ? "Saved!" : "Save Configuration")
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
                    Text("Uninstall")
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
                    Text("Install")
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
