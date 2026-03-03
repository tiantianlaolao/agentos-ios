import SwiftUI

struct AttachmentPreviewView: View {
    let attachments: [Attachment]
    let onRemove: (Int) -> Void
    private let serverBaseURL = "http://43.155.104.45:3100"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZStack(alignment: .topTrailing) {
                        if attachment.type == .image {
                            AsyncImage(url: URL(string: "\(serverBaseURL)\(attachment.url)")) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            VStack {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppTheme.primary)
                                Text(attachment.name)
                                    .font(.system(size: 8))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 60, height: 60)
                            .background(AppTheme.surfaceLight.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button(action: { onRemove(index) }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                                .background(Circle().fill(Color.black))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppTheme.background)
    }
}
