import SwiftUI

struct RegisterSkillView: View {
    let serverUrl: String
    let authToken: String
    let onRegistered: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var endpointUrl = ""
    @State private var funcName = ""
    @State private var funcDesc = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

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
                        formField(label: "Skill Name *", placeholder: "my-skill", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        formField(label: "Description", placeholder: "What does this skill do?", text: $description, multiline: true)

                        formField(label: "Endpoint URL *", placeholder: "https://my-server.com/api/skill", text: $endpointUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        Text("Function Definition")
                            .font(AppTheme.bodyFont.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)

                        formField(label: "Function Name *", placeholder: "do_something", text: $funcName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        formField(label: "Function Description", placeholder: "Describe what this function does", text: $funcDesc)

                        Text("Your endpoint will receive POST requests with {\"function\": \"<name>\", \"args\": {...}} and should return a JSON response.")
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
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Register Skill")
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
            .navigationTitle("Register External Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private func formField(label: String, placeholder: String, text: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            if multiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            } else {
                TextField(placeholder, text: text)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            }
        }
    }

    private func handleSubmit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUrl = endpointUrl.trimmingCharacters(in: .whitespaces)
        let trimmedFuncName = funcName.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty, !trimmedUrl.isEmpty, !trimmedFuncName.isEmpty else {
            errorMessage = "Name, endpoint URL, and at least one function are required."
            return
        }

        let namePattern = /^[a-z0-9-]+$/
        guard trimmedName.wholeMatch(of: namePattern) != nil else {
            errorMessage = "Skill name must contain only lowercase letters, digits, and hyphens."
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            guard let url = URL(string: "\(baseUrl)/skills/register") else {
                errorMessage = "Invalid URL"
                isLoading = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "name": trimmedName,
                "description": description.trimmingCharacters(in: .whitespaces),
                "endpointUrl": trimmedUrl,
                "functions": [
                    [
                        "name": trimmedFuncName,
                        "description": funcDesc.trimmingCharacters(in: .whitespaces).isEmpty ? trimmedFuncName : funcDesc.trimmingCharacters(in: .whitespaces),
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "input": [
                                    "type": "string",
                                    "description": "Input for the function"
                                ]
                            ],
                            "required": ["input"]
                        ]
                    ]
                ]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isLoading = false
                return
            }

            if http.statusCode == 200 {
                onRegistered()
                dismiss()
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = error
                } else {
                    errorMessage = "Registration failed"
                }
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
