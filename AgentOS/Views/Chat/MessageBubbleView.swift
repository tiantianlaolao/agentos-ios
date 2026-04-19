import SwiftUI
import MarkdownUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onBacktestAction: ((BacktestAction) -> Void)?
    var showAvatar: Bool = false

    @State private var selectedImageURL: URL?

    private var serverBaseURL: String { ServerConfig.shared.httpBaseURL }

    var body: some View {
        let isUser = message.role == .user

        HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 60) }

            // Assistant avatar
            if !isUser {
                if showAvatar {
                    let avatarState: AvatarState = message.skillName == "push" ? .proactive : .idle
                    AssistantAvatarView(size: .small, state: avatarState, animated: false)
                } else {
                    Color.clear.frame(width: 32, height: 32)
                }
            }

            bubbleContent(isUser: isUser)

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
    private func actionIcons(isUser: Bool) -> some View {
        HStack(spacing: 8) {
            Button { onCopy() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(isUser ? .white.opacity(0.5) : AppTheme.textTertiary)
            }
            // Compare button removed 2026-04-19 (feature retired)
            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(isUser ? .white.opacity(0.5) : AppTheme.textTertiary)
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func attachmentViews(isUser: Bool) -> some View {
        if let attachments = message.attachments, !attachments.isEmpty {
            ForEach(attachments) { attachment in
                if attachment.type == .image {
                    let rawUrl = attachment.url.hasPrefix("http") ? attachment.url : "\(serverBaseURL)\(attachment.url)"
                    let url = URL(string: rawUrl)
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
            // User bubble - attachments + text + time + actions inside
            VStack(alignment: .trailing, spacing: 4) {
                attachmentViews(isUser: true)
                if !message.content.isEmpty {
                    SelectableTextView(text: message.content, isUserBubble: true)
                }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(timeStr)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                    actionIcons(isUser: true)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
        } else if message.skillName == "push" {
            // Proactive push bubble
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("chat.proactiveLabel"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#C4845A"))
                attachmentViews(isUser: false)
                if !message.content.isEmpty {
                    SelectableContentView(content: message.content)
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("由 AI 生成")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    Text(timeStr)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    actionIcons(isUser: false)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#FFF8F0"), Color(hex: "#FEF3EA")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(Color(hex: "#F0DECE"), lineWidth: 1)
            )
            .overlay(
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.25)
                        .fill(AppTheme.primary)
                        .frame(width: 2.5)
                        .padding(.vertical, 6)
                    Spacer()
                }
            )
        } else {
            // Assistant bubble - attachments + markdown + time inside
            VStack(alignment: .leading, spacing: 4) {
                // Compare model tag removed 2026-04-19 (feature retired)
                attachmentViews(isUser: false)
                if !message.content.isEmpty {
                    SelectableContentView(content: message.content)
                }
                // Backtest workstation action button
                if let action = message.backtestAction {
                    Button {
                        onBacktestAction?(action)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 12))
                            Text(action.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 6)
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("由 AI 生成")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    Text(timeStr)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.6))
                    actionIcons(isUser: false)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.assistantBubble)
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Selectable Content (text selectable, code blocks tap-to-copy)

struct SelectableContentView: View {
    let content: String

    private enum Segment: Identifiable {
        case text(String)
        case code(language: String, code: String)

        var id: String {
            switch self {
            case .text(let s): return "t:\(s.prefix(40))"
            case .code(_, let s): return "c:\(s.prefix(40))"
            }
        }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        let pattern = "```(\\w*)\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(content)]
        }
        let nsContent = content as NSString
        var lastEnd = 0
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let textPart = nsContent.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !textPart.isEmpty {
                    result.append(.text(textPart))
                }
            }
            let lang = match.numberOfRanges > 1 ? nsContent.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsContent.substring(with: match.range(at: 2)) : ""
            result.append(.code(language: lang, code: code.trimmingCharacters(in: .newlines)))
            lastEnd = matchRange.location + matchRange.length
        }
        if lastEnd < nsContent.length {
            let remaining = nsContent.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                result.append(.text(remaining))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                switch segment {
                case .text(let text):
                    SelectableTextView(text: text)
                case .code(let language, let code):
                    CodeBlockView(code: code, language: language)
                }
            }
        }
    }
}

// MARK: - Native selectable text (UITextView wrapper)

struct SelectableTextView: UIViewRepresentable {
    let text: String
    var isUserBubble: Bool = false

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.font = .systemFont(ofSize: 16)
        tv.textColor = isUserBubble ? .white : UIColor(AppTheme.textPrimary)
        tv.dataDetectorTypes = [.link]
        tv.linkTextAttributes = [.foregroundColor: isUserBubble ? UIColor.white.withAlphaComponent(0.8) : UIColor(AppTheme.primaryLight)]
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
        tv.textColor = isUserBubble ? .white : UIColor(AppTheme.textPrimary)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 60
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
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
    var showAvatar: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if showAvatar {
                AssistantAvatarView(size: .small, animated: false)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

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
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(AppTheme.border, lineWidth: 1)
            )

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
            ForegroundColor(Color(hex: "#2D2620"))
            BackgroundColor(AppTheme.surfaceLight)
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
            .background(AppTheme.surfaceLight)
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
