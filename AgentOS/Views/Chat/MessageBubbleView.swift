import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let isUser = message.role == .user

        HStack(alignment: .top, spacing: AppTheme.paddingMedium) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                // Assistant avatar
                Circle()
                    .fill(AppTheme.surfaceLight)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.primary)
                    }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Bubble
                bubbleContent(isUser: isUser)
                    .contextMenu {
                        Button {
                            onCopy()
                        } label: {
                            Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }

                // Timestamp
                Text(Date.fromTimestamp(message.timestamp).chatTimeLabel())
                    .font(AppTheme.smallFont)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, AppTheme.paddingLarge)
    }

    @ViewBuilder
    private func bubbleContent(isUser: Bool) -> some View {
        let isError = message.content.hasPrefix("[Error]")

        if isUser {
            Text(message.content)
                .font(AppTheme.bodyFont)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        } else if isError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.error)
                Text(message.content.replacingOccurrences(of: "[Error] ", with: ""))
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.error)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.error.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        } else {
            Markdown(message.content)
                .markdownTheme(MarkdownThemeProvider.agentOS)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.assistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
    }
}

// MARK: - Streaming Bubble (for in-progress content)

struct StreamingBubbleView: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.paddingMedium) {
            // Assistant avatar
            Circle()
                .fill(AppTheme.surfaceLight)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primary)
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    Markdown(content)
                        .markdownTheme(MarkdownThemeProvider.agentOS)
                    StreamingCursorView()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.assistantBubble)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppTheme.paddingLarge)
    }
}

// MARK: - Date Separator

struct DateSeparatorView: View {
    let label: String

    var body: some View {
        HStack {
            VStack { Divider().background(AppTheme.divider) }
            Text(label)
                .font(AppTheme.smallFont)
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize()
            VStack { Divider().background(AppTheme.divider) }
        }
        .padding(.horizontal, AppTheme.paddingXLarge)
        .padding(.vertical, AppTheme.paddingMedium)
    }
}

// MARK: - MarkdownUI Theme

@MainActor
enum MarkdownThemeProvider {
    static let agentOS = MarkdownUI.Theme()
        .text {
            ForegroundColor(AppTheme.textPrimary)
            FontSize(15)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(AppTheme.accent)
        }
        .link {
            ForegroundColor(AppTheme.primaryLight)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 12, bottom: 8)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(18)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 10, bottom: 6)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(16)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                        ForegroundColor(AppTheme.textPrimary)
                    }
                    .padding(12)
            }
            .background(Color(hex: "#0D0D0D"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .markdownMargin(top: 8, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(AppTheme.textSecondary)
                        FontSize(14)
                    }
                    .padding(.leading, 10)
            }
            .markdownMargin(top: 4, bottom: 4)
        }
}
