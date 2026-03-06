import SwiftUI
import UniformTypeIdentifiers

struct ImportSkillMdView: View {
    let serverUrl: String
    let authToken: String
    var agentType: String = "builtin"
    let onImported: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var fileName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showFilePicker = false

    private var baseUrl: String {
        serverUrl.replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "/ws", with: "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.tr("skills.importSkillMdIntro"))
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textSecondary)

                        // File picker button
                        Button {
                            showFilePicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(AppTheme.primary)
                                Text(L10n.tr("skills.chooseFile"))
                                    .font(AppTheme.bodyFont.weight(.semibold))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                    .foregroundStyle(AppTheme.primary)
                            )
                        }

                        if !fileName.isEmpty {
                            Text(L10n.tr("skills.selected", ["name": fileName]))
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.success)
                        }

                        Text(L10n.tr("skills.skillMdContent"))
                            .font(AppTheme.captionFont.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        TextEditor(text: $content)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 200)
                            .padding(12)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                            .onChange(of: content) {
                                if !fileName.isEmpty { fileName = "" }
                            }

                        Text(L10n.tr("skills.skillMdFormatHint"))
                            .font(AppTheme.smallFont)
                            .foregroundStyle(AppTheme.textTertiary)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.error)
                        }

                        Button {
                            Task { await handleSubmit() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(L10n.tr("skills.importBtn"))
                                }
                            }
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.6 : 1)
                    }
                    .padding(AppTheme.paddingLarge)
                }
            }
            .navigationTitle(L10n.tr("skills.skillMdTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("skills.cancel")) { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        content = text
                        fileName = url.lastPathComponent
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleSubmit() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L10n.tr("skills.provideSkillMd")
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            guard let url = URL(string: "\(baseUrl)/skills/md/upload") else {
                errorMessage = "Invalid URL"
                isLoading = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            var bodyDict: [String: Any] = ["content": content.trimmingCharacters(in: .whitespacesAndNewlines)]
            if agentType != "builtin" {
                bodyDict["agentType"] = agentType
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isLoading = false
                return
            }

            if http.statusCode == 200 {
                onImported()
                dismiss()
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = error
                } else {
                    errorMessage = "Import failed"
                }
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
