import Foundation

/// Direct LLM streaming service for BYOK mode.
/// Calls LLM provider APIs directly from the device; API keys never leave the device.
final class DirectLLMService: Sendable {
    static let shared = DirectLLMService()

    private init() {}

    // MARK: - Provider config

    struct ProviderConfig: Sendable {
        let baseUrl: String
        let defaultModel: String
    }

    static let providerConfigs: [LLMProvider: ProviderConfig] = [
        .deepseek: ProviderConfig(baseUrl: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        .openai: ProviderConfig(baseUrl: "https://api.openai.com", defaultModel: "gpt-4o"),
        .moonshot: ProviderConfig(baseUrl: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-auto"),
        .anthropic: ProviderConfig(baseUrl: "https://api.anthropic.com", defaultModel: "claude-sonnet-4-5-20250929"),
    ]

    private static let systemPrompt =
        "You are AgentOS Assistant, a helpful AI assistant. " +
        "Keep responses concise and helpful. Respond in the same language the user uses."

    // MARK: - Public API

    /// Stream a chat completion directly from an LLM provider.
    /// Calls `onChunk` for each text delta, `onDone` when complete, `onError` on failure.
    func streamChat(
        provider: LLMProvider,
        apiKey: String,
        model: String?,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void,
        onDone: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async {
        guard let config = Self.providerConfigs[provider] else {
            onError("Unknown provider: \(provider.rawValue)")
            return
        }

        let modelToUse = model ?? config.defaultModel

        do {
            if provider == .anthropic {
                try await streamAnthropic(
                    baseUrl: config.baseUrl, apiKey: apiKey, model: modelToUse,
                    messages: messages, onChunk: onChunk, onDone: onDone
                )
            } else {
                try await streamOpenAICompatible(
                    baseUrl: config.baseUrl, apiKey: apiKey, model: modelToUse,
                    messages: messages, onChunk: onChunk, onDone: onDone
                )
            }
        } catch is CancellationError {
            return
        } catch {
            onError(error.localizedDescription)
        }
    }

    // MARK: - OpenAI-compatible (DeepSeek, OpenAI, Moonshot)

    private func streamOpenAICompatible(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void,
        onDone: @escaping @Sendable (String) -> Void
    ) async throws {
        let urlString = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions"
        guard let url = URL(string: urlString) else { throw DirectLLMError.invalidURL }

        var allMessages: [[String: String]] = [["role": "system", "content": Self.systemPrompt]]
        allMessages += messages.map { ["role": $0.role, "content": $0.content] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectLLMError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 200 { break }
            }
            throw DirectLLMError.httpError(httpResponse.statusCode, errorBody)
        }

        var fullContent = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            if data == "[DONE]" { break }

            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }

            fullContent += content
            onChunk(content)
        }

        onDone(fullContent)
    }

    // MARK: - Anthropic Messages API

    private func streamAnthropic(
        baseUrl: String,
        apiKey: String,
        model: String,
        messages: [(role: String, content: String)],
        onChunk: @escaping @Sendable (String) -> Void,
        onDone: @escaping @Sendable (String) -> Void
    ) async throws {
        let urlString = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/messages"
        guard let url = URL(string: urlString) else { throw DirectLLMError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let apiMessages = messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": Self.systemPrompt,
            "messages": apiMessages,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectLLMError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 200 { break }
            }
            throw DirectLLMError.httpError(httpResponse.statusCode, errorBody)
        }

        var fullContent = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)

            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            let eventType = json["type"] as? String
            if eventType == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                fullContent += text
                onChunk(text)
            }
        }

        onDone(fullContent)
    }

    // MARK: - Errors

    enum DirectLLMError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .invalidResponse: return "Invalid response from API"
            case .httpError(let code, let body):
                let truncated = body.prefix(200)
                return "\(code): \(truncated)"
            }
        }
    }
}
