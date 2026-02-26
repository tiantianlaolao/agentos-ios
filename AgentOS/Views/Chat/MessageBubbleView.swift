import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let isUser = message.role == .user

        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 50) }

            if !isUser {
                // Assistant avatar - compact
                Circle()
                    .fill(AppTheme.surfaceLight)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.primary)
                    }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 1) {
                // Bubble
                bubbleContent(isUser: isUser)
                    .contextMenu {
                        Button {
                            onCopy()
                        } label: {
                            Label(L10n.tr("chat.copy"), systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label(L10n.tr("chat.deleteMessage"), systemImage: "trash")
                        }
                    }

                // Timestamp - subtle
                Text(Date.fromTimestamp(message.timestamp).chatTimeLabel())
                    .font(AppTheme.chatTimeFont)
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
                    .padding(.horizontal, 4)
            }

            if !isUser { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func bubbleContent(isUser: Bool) -> some View {
        let isError = message.content.hasPrefix("[Error]")

        if isUser {
            Text(message.content)
                .font(AppTheme.chatBodyFont)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.userBubble)
                .clipShape(ChatBubbleShape(isUser: true))
        } else if isError {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.error)
                Text(message.content.replacingOccurrences(of: "[Error] ", with: ""))
                    .font(AppTheme.chatSmallFont)
                    .foregroundStyle(AppTheme.error)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.error.opacity(0.1))
            .clipShape(ChatBubbleShape(isUser: false))
        } else {
            Markdown(message.content)
                .markdownTheme(MarkdownThemeProvider.agentOS)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.assistantBubble)
                .clipShape(ChatBubbleShape(isUser: false))
        }
    }
}

// MARK: - Chat Bubble Shape (WeChat/Telegram style with tail)

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = AppTheme.chatBubbleRadius
        let tailR: CGFloat = AppTheme.chatBubbleRadiusSmall

        if isUser {
            // User: rounded with small bottom-right corner
            return Path(
                roundedRect: rect,
                cornerRadii: .init(
                    topLeading: r,
                    bottomLeading: r,
                    bottomTrailing: tailR,
                    topTrailing: r
                )
            )
        } else {
            // Assistant: rounded with small bottom-left corner
            return Path(
                roundedRect: rect,
                cornerRadii: .init(
                    topLeading: r,
                    bottomLeading: tailR,
                    bottomTrailing: r,
                    topTrailing: r
                )
            )
        }
    }
}

// MARK: - Streaming Bubble (for in-progress content)

struct StreamingBubbleView: View {
    let content: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            // Assistant avatar
            Circle()
                .fill(AppTheme.surfaceLight)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.primary)
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    Markdown(content)
                        .markdownTheme(MarkdownThemeProvider.agentOS)
                    StreamingCursorView()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.assistantBubble)
                .clipShape(ChatBubbleShape(isUser: false))
            }

            Spacer(minLength: 50)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }
}

// MARK: - Date Separator

struct DateSeparatorView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(AppTheme.surfaceLight.opacity(0.5))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
                    FontSize(18)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(16)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 6, bottom: 3)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    ForegroundColor(AppTheme.textPrimary)
                }
                .markdownMargin(top: 4, bottom: 2)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(12)
                        ForegroundColor(AppTheme.textPrimary)
                    }
                    .padding(10)
            }
            .background(Color(hex: "#0D0D0D"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 4, bottom: 4)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(width: 2)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(AppTheme.textSecondary)
                        FontSize(14)
                    }
                    .padding(.leading, 8)
            }
            .markdownMargin(top: 2, bottom: 2)
        }
}
