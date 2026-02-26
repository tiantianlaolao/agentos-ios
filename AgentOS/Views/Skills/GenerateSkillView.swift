import SwiftUI

private struct GenerateResult {
    let content: String
    let name: String
    let description: String
    let emoji: String
}

struct GenerateSkillView: View {
    let serverUrl: String
    let authToken: String
    let onGenerated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var isGenerating = false
    @State private var isImporting = false
    @State private var errorMessage = ""
    @State private var result: GenerateResult?

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
                        Text("Describe the skill you want and AI will generate a SKILL.md definition for you.")
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textSecondary)

                        Text("Description")
                            .font(AppTheme.captionFont.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)

                        TextField("e.g. A skill that can translate text between languages", text: $description, axis: .vertical)
                            .lineLimit(4...8)
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(12)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                            .disabled(isGenerating)

                        Button {
                            Task { await handleGenerate() }
                        } label: {
                            HStack(spacing: 8) {
                                if isGenerating {
                                    ProgressView().tint(.white)
                                    Text("Generating...")
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Generate")
                                }
                            }
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .disabled(isGenerating)
                        .opacity(isGenerating ? 0.6 : 1)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.error)
                        }

                        // Preview
                        if let result {
                            previewSection(result)
                        }
                    }
                    .padding(AppTheme.paddingLarge)
                }
            }
            .navigationTitle("AI Generate Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Preview

    private func previewSection(_ result: GenerateResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textPrimary)

            VStack(spacing: 8) {
                Text(result.emoji)
                    .font(.system(size: 36))
                Text(result.name)
                    .font(AppTheme.headlineFont)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(result.description)
                    .font(AppTheme.captionFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            Text("SKILL.md")
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            ScrollView {
                Text(result.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

            Button {
                Task { await handleConfirmImport(result) }
            } label: {
                Group {
                    if isImporting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm & Import")
                    }
                }
                .font(AppTheme.bodyFont.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            }
            .disabled(isImporting)
            .opacity(isImporting ? 0.6 : 1)
        }
    }

    // MARK: - Network

    private func handleGenerate() async {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please describe the skill you want."
            return
        }

        isGenerating = true
        errorMessage = ""
        result = nil

        do {
            guard let url = URL(string: "\(baseUrl)/skills/md/generate") else {
                errorMessage = "Invalid URL"
                isGenerating = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["description": description.trimmingCharacters(in: .whitespaces)])
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isGenerating = false
                return
            }

            if http.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let content = json["content"] as? String ?? ""
                    let parsed = json["parsed"] as? [String: Any] ?? [:]
                    result = GenerateResult(
                        content: content,
                        name: parsed["name"] as? String ?? "",
                        description: parsed["description"] as? String ?? "",
                        emoji: parsed["emoji"] as? String ?? ""
                    )
                }
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = error
                } else {
                    errorMessage = "Generation failed"
                }
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    private func handleConfirmImport(_ result: GenerateResult) async {
        isImporting = true
        errorMessage = ""

        do {
            guard let url = URL(string: "\(baseUrl)/skills/md/upload") else {
                errorMessage = "Invalid URL"
                isImporting = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["content": result.content])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isImporting = false
                return
            }

            if http.statusCode == 200 {
                onGenerated()
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

        isImporting = false
    }
}
