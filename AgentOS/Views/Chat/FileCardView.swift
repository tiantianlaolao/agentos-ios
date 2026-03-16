import SwiftUI

struct FileCardView: View {
    let attachment: Attachment
    private var serverBaseURL: String { ServerConfig.shared.httpBaseURL }

    private var iconName: String {
        switch attachment.mimeType {
        case let m where m.contains("pdf"): return "doc.richtext"
        case let m where m.contains("word") || m.contains("document"): return "doc.text"
        case let m where m.contains("spreadsheet") || m.contains("excel"): return "tablecells"
        case let m where m.contains("text") || m.contains("markdown"): return "doc.plaintext"
        default: return "doc"
        }
    }

    private var sizeString: String {
        if attachment.size < 1024 {
            return "\(attachment.size) B"
        } else if attachment.size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(attachment.size) / 1024)
        } else {
            return String(format: "%.1f MB", Double(attachment.size) / (1024 * 1024))
        }
    }

    var body: some View {
        Button(action: shareFile) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.primary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(sizeString)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(10)
            .background(AppTheme.surfaceLight.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func shareFile() {
        guard let url = URL(string: "\(serverBaseURL)\(attachment.url)") else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.name)
            try? data.write(to: tempURL)
            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(activityVC, animated: true)
                }
            }
        }
    }
}
