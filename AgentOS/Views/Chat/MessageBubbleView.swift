import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onCompare: ((String) -> Void)?

    @State private var selectedImageURL: URL?

    private let serverBaseURL = "http://43.155.104.45:3100"

    var body: some View {
        let isUser = message.role == .user

        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            bubbleContent(isUser: isUser)
                .contextMenu {
                    Button {
                        onCopy()
                    } label: {
                        Label(L10n.tr("chat.copy"), systemImage: "doc.on.doc")
                    }
                    if !isUser && message.compareModel == nil && !message.content.hasPrefix("[Error]") && onCompare != nil {
                        Button {
                            onCompare?(message.content)
                        } label: {
                            Label(L10n.tr("chat.compare"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(L10n.tr("chat.deleteMessage"), systemImage: "trash")
                    }
                }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .fullScreenCover(isPresented: Binding(
            get: { selectedImageURL != nil },
            set: { if !$0 { selectedImageURL = nil } }
        )) {
            if let url = selectedImageURL {
                ImageViewerView(imageURL: url)
            }
        }
    }

    @ViewBuilder
    private func attachmentViews(isUser: Bool) -> some View {
        if let attachments = message.attachments, !attachments.isEmpty {
            ForEach(attachments) { attachment in
                if attachment.type == .image {
                    let url = URL(string: "\(serverBaseURL)\(attachment.url)")
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { selectedImageURL = url }
                } else {
                    FileCardView(attachment: attachment)
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleContent(isUser: Bool) -> some View {
        let isError = message.content.hasPrefix("[Error]")
        let timeStr = Date.fromTimestamp(message.timestamp).chatTimeLabel()

        if isUser {
            // User bubble - attachments + text + time inside
            VStack(alignment: .trailing, spacing: 4) {
                attachmentViews(isUser: true)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(timeStr)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.userBubble)
            .clipShape(BubbleShape(isUser: true))
        } else if isError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.error)
                Text(message.content.replacingOccurrences(of: "[Error] ", with: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.error)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.error.opacity(0.1))
            .clipShape(BubbleShape(isUser: false))
        } else {
            // Assistant bubble - attachments + markdown + time inside
            VStack(alignment: .leading, spacing: 4) {
                if let modelName = message.compareModel {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                        Text(modelName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
                attachmentViews(isUser: false)
                if !message.content.isEmpty {
                    Markdown(message.content)
                        .markdownTheme(MarkdownThemeProvider.agentOS)
                        .textSelection(.enabled)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(timeStr)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.assistantBubble)
            .clipShape(BubbleShape(isUser: false))
        }
    }
}

// MARK: - Bubble Shape (Telegram-style rounded corners)

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16
        let small: CGFloat = 4

        if isUser {
            return Path(
                roundedRect: rect,
                cornerRadii: .init(
                    topLeading: r,
                    bottomLeading: r,
                    bottomTrailing: small,
                    topTrailing: r
                )
            )
        } else {
            return Path(
                roundedRect: rect,
                cornerRadii: .init(
                    topLeading: r,
                    bottomLeading: small,
                    bottomTrailing: r,
                    topTrailing: r
                )
            )
        }
    }
}

// MARK: - Streaming Bubble

struct StreamingBubbleView: View {
    let content: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    Markdown(content)
                        .markdownTheme(MarkdownThemeProvider.agentOS)
                    StreamingCursorView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.assistantBubble)
            .clipShape(BubbleShape(isUser: false))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }
}

// MARK: - Date Separator

struct DateSeparatorView: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(AppTheme.surfaceLight.opacity(0.6))
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
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(14)
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
                        FontSize(13)
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
