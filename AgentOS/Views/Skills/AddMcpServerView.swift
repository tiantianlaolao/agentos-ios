import SwiftUI

private struct McpServer: Identifiable {
    let name: String
    let command: String
    let args: [String]
    let enabled: Bool
    let connected: Bool
    let system: Bool
    let toolCount: Int
    let location: String  // "server" or "local"

    var id: String { name }
}

struct AddMcpServerView: View {
    let serverUrl: String
    let authToken: String
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servers: [McpServer] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showAddForm = false

    // Add form
    @State private var name = ""
    @State private var command = ""
    @State private var args = ""
    @State private var isAdding = false
    @State private var location: String = "server"

    private var baseUrl: String {
        serverUrl.replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "/ws", with: "")
    }

    private static let localOnlyPatterns = [
        "chrome-devtools-mcp", "puppeteer", "server-puppeteer",
        "playwright", "browser-tools", "browser-use"
    ]

    private func detectLocation() -> String {
        let fullArgs = "\(command) \(args)".lowercased()
        return Self.localOnlyPatterns.contains(where: { fullArgs.contains($0) }) ? "local" : "server"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.tr("skills.connectMcpIntro"))
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.textSecondary)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.error)
                        }

                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView().tint(AppTheme.primary)
                                Spacer()
                            }
                            .padding(.vertical, 24)
                        } else {
                            // Server list
                            ForEach(servers) { server in
                                serverCard(server)
                            }

                            if servers.isEmpty {
                                Text(L10n.tr("skills.noMcpServers"))
                                    .font(AppTheme.bodyFont)
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                        }

                        // Add form / button
                        if showAddForm {
                            addFormView
                        } else {
                            Button {
                                showAddForm = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                    Text(L10n.tr("skills.addMcpServer"))
                                }
                                .font(AppTheme.captionFont.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                        .foregroundStyle(AppTheme.border)
                                )
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(AppTheme.paddingLarge)
                }
            }
            .navigationTitle(L10n.tr("skills.mcpTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("skills.done")) { dismiss() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .task {
            await fetchServers()
        }
    }

    // MARK: - Server Card

    private func serverCard(_ server: McpServer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(server.connected ? AppTheme.success : AppTheme.error)
                        .frame(width: 8, height: 8)
                    Text(server.name)
                        .font(AppTheme.bodyFont.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if server.toolCount > 0 {
                        Text("\(server.toolCount) \(L10n.tr("skills.tools"))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppTheme.primary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if server.system {
                        Text(L10n.tr("skills.system"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppTheme.success.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if server.location == "local" {
                        Text("Local")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if !server.system {
                    Button {
                        Task { await deleteServer(server.name) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.error)
                    }
                }
            }

            Text("\(server.command) \(server.args.joined(separator: " "))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Add Form

    private var addFormView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("skills.name"))
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(L10n.tr("skills.mcpNamePlaceholder"), text: $name)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

            Text(L10n.tr("skills.command"))
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(L10n.tr("skills.mcpCommandPlaceholder"), text: $command)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

            Text(L10n.tr("skills.args"))
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(L10n.tr("skills.mcpArgsPlaceholder"), text: $args)
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
            Text(L10n.tr("skills.commaSeparated"))
                .font(AppTheme.smallFont)
                .foregroundStyle(AppTheme.textTertiary)

            // Location picker
            Text("Location")
                .font(AppTheme.captionFont.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 4)
            Picker("Location", selection: $location) {
                Text("Server").tag("server")
                Text("Local Computer").tag("local")
            }
            .pickerStyle(.segmented)
            .onChange(of: command) { _, _ in location = detectLocation() }
            .onChange(of: args) { _, _ in location = detectLocation() }

            if location == "local" {
                Text("This tool will run on your local computer (requires desktop app)")
                    .font(AppTheme.smallFont)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await handleAdd() }
                } label: {
                    Group {
                        if isAdding {
                            ProgressView().tint(.white)
                        } else {
                            Text(L10n.tr("skills.addServer"))
                        }
                    }
                    .font(AppTheme.bodyFont.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
                .disabled(isAdding || name.trimmingCharacters(in: .whitespaces).isEmpty || command.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(isAdding || name.trimmingCharacters(in: .whitespaces).isEmpty || command.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)

                Button {
                    showAddForm = false
                    name = ""
                    command = ""
                    args = ""
                    location = "server"
                } label: {
                    Text(L10n.tr("skills.cancel"))
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(AppTheme.surfaceLighter)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    // MARK: - Network

    private func fetchServers() async {
        isLoading = true
        errorMessage = ""
        do {
            guard let url = URL(string: "\(baseUrl)/mcp/servers") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serversArray = json["servers"] as? [[String: Any]] {
                servers = serversArray.map { dict in
                    let tools = dict["tools"] as? [Any] ?? []
                    return McpServer(
                        name: dict["name"] as? String ?? "",
                        command: dict["command"] as? String ?? "",
                        args: dict["args"] as? [String] ?? [],
                        enabled: dict["enabled"] as? Bool ?? true,
                        connected: dict["connected"] as? Bool ?? false,
                        system: dict["system"] as? Bool ?? false,
                        toolCount: tools.count,
                        location: dict["location"] as? String ?? "server"
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func handleAdd() async {
        isAdding = true
        errorMessage = ""
        do {
            guard let url = URL(string: "\(baseUrl)/mcp/servers") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

            let argsArray = args.trimmingCharacters(in: .whitespaces).isEmpty
                ? []
                : args.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            let body: [String: Any] = [
                "name": name.trimmingCharacters(in: .whitespaces),
                "command": command.trimmingCharacters(in: .whitespaces),
                "args": argsArray,
                "location": location
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = error
                } else {
                    errorMessage = "Failed to add server"
                }
                isAdding = false
                return
            }

            name = ""
            command = ""
            args = ""
            location = "server"
            showAddForm = false
            await fetchServers()
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
        isAdding = false
    }

    private func deleteServer(_ serverName: String) async {
        errorMessage = ""
        do {
            guard let url = URL(string: "\(baseUrl)/mcp/servers/\(serverName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serverName)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            _ = try await URLSession.shared.data(for: request)
            await fetchServers()
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
