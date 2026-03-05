import SwiftUI

struct CompareModel: Codable, Identifiable {
    let id: String
    let name: String
    let provider: String
}

struct CompareModelSheet: View {
    let onSelect: (String, String) -> Void
    let onDismiss: () -> Void

    @State private var models: [CompareModel] = []
    @State private var isLoading = true
    @State private var errorText: String?

    private let serverBaseURL = "http://43.155.104.45:3100"

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(AppTheme.primary)
                } else if let error = errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(error)
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(models) { model in
                                Button {
                                    onSelect(model.id, model.name)
                                    onDismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model.name)
                                                .font(AppTheme.bodyFont.weight(.medium))
                                                .foregroundStyle(AppTheme.textPrimary)
                                            Text(model.provider)
                                                .font(AppTheme.captionFont)
                                                .foregroundStyle(AppTheme.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }
                                    .padding(14)
                                    .background(AppTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppTheme.paddingLarge)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(L10n.tr("chat.selectModel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("chat.cancel")) { onDismiss() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .task {
            await fetchModels()
        }
    }

    private func fetchModels() async {
        guard let url = URL(string: "\(serverBaseURL)/api/compare-models") else {
            errorText = "Invalid URL"
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([CompareModel].self, from: data)
            models = decoded
            isLoading = false
        } catch {
            errorText = error.localizedDescription
            isLoading = false
        }
    }
}
