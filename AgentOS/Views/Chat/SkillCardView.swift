import SwiftUI

struct SkillCardView: View {
    let skill: SkillExecution

    var body: some View {
        HStack(spacing: AppTheme.paddingStandard) {
            // Status icon
            if skill.isRunning {
                ProgressView()
                    .tint(AppTheme.accent)
                    .controlSize(.small)
            } else if skill.success == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppTheme.error)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(AppTheme.captionFont.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(skill.description)
                    .font(AppTheme.smallFont)
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(AppTheme.paddingStandard)
        .background(AppTheme.surfaceLight)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .padding(.horizontal, AppTheme.paddingLarge)
    }
}
