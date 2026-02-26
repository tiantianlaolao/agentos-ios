import SwiftUI

struct AgentCard: Identifiable {
    let id: ConnectionMode
    let name: String
    let description: String
    let icon: String
    let color: Color
}

private let agentCards: [AgentCard] = [
    AgentCard(
        id: .builtin,
        name: "Builtin Agent",
        description: "Default AI assistant",
        icon: "cpu",
        color: AppTheme.success
    ),
    AgentCard(
        id: .openclaw,
        name: "OpenClaw",
        description: "Personal AI with skills",
        icon: "hand.raised",
        color: AppTheme.warning
    ),
    AgentCard(
        id: .copaw,
        name: "CoPaw",
        description: "Collaborative agent",
        icon: "pawprint",
        color: AppTheme.primary
    ),
]

struct AgentHubView: View {
    let currentMode: ConnectionMode
    let isConnected: Bool
    let onSelect: (ConnectionMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.paddingStandard) {
                ForEach(agentCards) { card in
                    AgentCardItemView(
                        card: card,
                        isSelected: card.id == currentMode,
                        isConnected: card.id == currentMode && isConnected,
                        onTap: { onSelect(card.id) }
                    )
                }
            }
            .padding(.horizontal, AppTheme.paddingLarge)
            .padding(.vertical, AppTheme.paddingMedium)
        }
    }
}

// MARK: - Card Item

private struct AgentCardItemView: View {
    let card: AgentCard
    let isSelected: Bool
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppTheme.paddingSmall) {
                HStack {
                    Image(systemName: card.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(card.color)

                    Spacer()

                    // Status indicator
                    if isSelected {
                        Circle()
                            .fill(isConnected ? AppTheme.success : AppTheme.warning)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(card.name)
                    .font(AppTheme.captionFont.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(card.description)
                    .font(AppTheme.smallFont)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(AppTheme.paddingStandard)
            .frame(width: 140)
            .background(isSelected ? card.color.opacity(0.15) : AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(isSelected ? card.color.opacity(0.5) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
