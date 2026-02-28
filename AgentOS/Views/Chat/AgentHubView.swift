import SwiftUI

struct AgentCard: Identifiable {
    let id: ConnectionMode
    let nameKey: String
    let descKey: String
    let icon: String
    let color: Color
}

private let agentCards: [AgentCard] = [
    AgentCard(
        id: .builtin,
        nameKey: "chat.tabBuiltin",
        descKey: "chat.tabBuiltinDesc",
        icon: "cpu",
        color: AppTheme.success
    ),
    AgentCard(
        id: .agent,
        nameKey: "chat.tabAgent",
        descKey: "chat.tabAgentDesc",
        icon: "bolt.fill",
        color: AppTheme.warning
    ),
]

struct AgentHubView: View {
    let currentMode: ConnectionMode
    let isConnected: Bool
    let onSelect: (ConnectionMode) -> Void
    let onManageSkills: () -> Void

    /// Map runtime modes to display card groups.
    /// openclaw/copaw/agent all map to the .agent card visually.
    private func displayGroup(for mode: ConnectionMode) -> ConnectionMode {
        switch mode {
        case .openclaw, .copaw, .agent: return .agent
        default: return mode
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title area
            VStack(spacing: 6) {
                Text(L10n.tr("chat.hubTitle"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(L10n.tr("chat.hubSubtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Agent cards
            VStack(spacing: 10) {
                ForEach(agentCards) { card in
                    AgentHubCardView(
                        card: card,
                        isSelected: card.id == displayGroup(for: currentMode),
                        isConnected: card.id == displayGroup(for: currentMode) && isConnected,
                        onTap: { onSelect(card.id) }
                    )
                }
            }
            .padding(.horizontal, 16)

            Spacer()

            // Manage Skills button
            Button(action: onManageSkills) {
                HStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 14))
                    Text(L10n.tr("chat.manageSkills"))
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.border, lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Agent Card Row

private struct AgentHubCardView: View {
    let card: AgentCard
    let isSelected: Bool
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(card.color.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: card.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(card.color)
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L10n.tr(card.nameKey))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        if isSelected {
                            Text(L10n.tr("chat.current"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(card.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(card.color.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(L10n.tr(card.descKey))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Connection dot
                if isSelected {
                    Circle()
                        .fill(isConnected ? AppTheme.success : AppTheme.warning)
                        .frame(width: 7, height: 7)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? card.color.opacity(0.06) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? card.color.opacity(0.3) : AppTheme.border.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
