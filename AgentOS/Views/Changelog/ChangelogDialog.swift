// L1 changelog dialog — pre (urge upgrade) / post (introduce new features) modes.
// Shown as a sheet from MainTabView when ChangelogService.pending* is set.
import SwiftUI

enum ChangelogDialogMode {
    case pre, post
}

struct ChangelogDialog: View {
    let entry: ChangelogEntry
    let mode: ChangelogDialogMode
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var locale: String {
        Locale.current.language.languageCode?.identifier == "zh" ? "zh" : "en"
    }
    private var isZh: Bool { locale == "zh" }

    private var items: [ChangelogItem] {
        isZh ? entry.changelog.zh : entry.changelog.en
    }
    private var lingxiMessage: String? {
        guard let m = entry.lingxi_message else { return nil }
        return isZh ? m.zh : m.en
    }

    private var canSkipDuringForceUpdate: Bool {
        !entry.force_update
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                AssistantAvatarView(size: .large, state: .happy, animated: false)
                    .padding(.top, 24)

                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 8) {
                    Text("v\(entry.version)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                    if entry.force_update {
                        Text(isZh ? "建议立即更新" : "Update Required")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }

            // Lingxi quote (if any)
            if let msg = lingxiMessage {
                HStack(alignment: .top, spacing: 8) {
                    Text("💬")
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.primary.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            // Items list (scrollable if many)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Text("·")
                                    .foregroundStyle(AppTheme.primary)
                                    .font(.system(size: 16, weight: .bold))
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(2)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 320)

            // Action buttons
            VStack(spacing: 8) {
                Button(action: primaryAction) {
                    HStack(spacing: 6) {
                        Image(systemName: primaryIcon)
                        Text(primaryButtonLabel)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if canSkipDuringForceUpdate {
                    Button(action: secondaryAction) {
                        Text(secondaryButtonLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(AppTheme.background)
        .interactiveDismissDisabled(entry.force_update)
    }

    // MARK: - Mode-specific labels & actions

    private var headerTitle: String {
        switch mode {
        case .pre:
            return isZh ? "灵犀有新版本啦" : "New Version Available"
        case .post:
            return isZh ? "灵犀升级了，看看新功能" : "What's New in This Version"
        }
    }

    private var primaryButtonLabel: String {
        switch mode {
        case .pre:
            return isZh ? "立即更新" : "Update Now"
        case .post:
            return isZh ? "我知道了" : "Got It"
        }
    }

    private var secondaryButtonLabel: String {
        switch mode {
        case .pre:
            return isZh ? "稍后" : "Later"
        case .post:
            return isZh ? "查看完整日志" : "View Full Changelog"
        }
    }

    private var primaryIcon: String {
        switch mode {
        case .pre: return "arrow.up.circle.fill"
        case .post: return "checkmark.circle.fill"
        }
    }

    private func primaryAction() {
        switch mode {
        case .pre:
            // Triggered update — open App Store + ack
            ChangelogService.shared.openAppStore(appStoreId: entry.platforms?.ios?.app_store_id)
            Task {
                await ChangelogService.shared.ack(version: entry.version, mode: .pre, action: .triggered_update)
            }
            onDismiss()
        case .post:
            // Acknowledged "got it" without viewing detail page
            Task {
                await ChangelogService.shared.ack(version: entry.version, mode: .post, action: .dismissed)
            }
            onDismiss()
        }
    }

    private func secondaryAction() {
        switch mode {
        case .pre:
            // "稍后" — DO NOT ack so dialog reappears next launch
            onDismiss()
        case .post:
            // Open changelog page + ack as clicked_detail
            ChangelogService.shared.openChangelogPage()
            Task {
                await ChangelogService.shared.ack(version: entry.version, mode: .post, action: .clicked_detail)
            }
            onDismiss()
        }
    }
}
