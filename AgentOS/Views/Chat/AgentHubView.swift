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
        id: .openclaw,
        nameKey: "chat.tabOpenclaw",
        descKey: "chat.tabOpenclawDesc",
        icon: "hand.raised",
        color: AppTheme.warning
    ),
    AgentCard(
        id: .copaw,
        nameKey: "chat.tabCopaw",
        descKey: "chat.tabCopawDesc",
        icon: "pawprint",
        color: AppTheme.primary
    ),
]

struct AgentHubView: View {
    let currentMode: ConnectionMode
    let isConnected: Bool
    let onSelect: (ConnectionMode) -> Void
    let onManageSkills: () -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 40)

                // Title
                VStack(spacing: 8) {
                    Text(L10n.tr("chat.hubTitle"))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(L10n.tr("chat.hubSubtitle"))
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .padding(.bottom, 32)

                // Agent cards
                VStack(spacing: 12) {
                    ForEach(agentCards) { card in
                        AgentHubCardView(
                            card: card,
                            isSelected: card.id == currentMode,
                            isConnected: card.id == currentMode && isConnected,
                            onTap: { onSelect(card.id) }
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                // Manage Skills button
                Button(action: onManageSkills) {
                    HStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 15))
                        Text(L10n.tr("chat.manageSkills"))
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Full-width Agent Card

private struct AgentHubCardView: View {
    let card: AgentCard
    let isSelected: Bool
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(card.color.opacity(0.15))
                        .frame(width: 46, height: 46)

                    Image(systemName: card.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(card.color)
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.tr(card.nameKey))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        if isSelected {
                            Text(L10n.tr("chat.current"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(card.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(card.color.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text(L10n.tr(card.descKey))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Connection indicator
                if isSelected {
                    Circle()
                        .fill(isConnected ? AppTheme.success : AppTheme.warning)
                        .frame(width: 8, height: 8)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? card.color.opacity(0.08) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isSelected ? card.color.opacity(0.4) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
