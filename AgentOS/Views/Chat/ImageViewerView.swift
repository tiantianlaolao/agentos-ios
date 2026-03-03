import SwiftUI

struct ImageViewerView: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = value.magnification
                            }
                            .onEnded { _ in
                                withAnimation { scale = max(1.0, scale) }
                            }
                    )
            } placeholder: {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: saveImage) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .padding()
        }
    }

    private func saveImage() {
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: imageURL),
                  let uiImage = UIImage(data: data) else { return }
            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
        }
    }
}
