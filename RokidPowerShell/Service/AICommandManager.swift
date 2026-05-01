import Foundation

/// Converts natural-language requests into PowerShell commands using an AI backend.
actor AICommandManager {

    // MARK: - Provider enum (public so ViewModel can use it)

    enum AIProvider: String, CaseIterable, Identifiable {
        case openAI = "openai"
        case claude = "claude"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .openAI: return "OpenAI (GPT-4o mini)"
            case .claude: return "Claude (Haiku)"
            }
        }

        var defaultModel: String {
            switch self {
            case .openAI: return "gpt-4o-mini"
            case .claude: return "claude-3-5-haiku-20241022"
            }
        }
    }

    // MARK: - System prompt

    private let systemPrompt = """
    You are a PowerShell expert. Convert the user's natural-language request into a PowerShell command or short script.

    Rules:
    - Reply with ONLY the PowerShell command(s), nothing else — no explanation, no markdown, no code fences
    - Prefer concise single-line commands
    - Use PowerShell 7 syntax where possible
    - If the user already typed a valid PowerShell command, return it unchanged
    - For irreversible/destructive operations (Remove-Item -Recurse, Format-*, Stop-Computer, etc.) append -WhatIf so the user can preview before running
    - If the request is ambiguous or cannot reasonably map to PowerShell, reply with: Write-Host "Unclear request — please rephrase"
    """

    // MARK: - Public entry point

    /// Converts `text` to a PowerShell command using the given provider + key.
    func convert(text: String,
                 provider: AIProvider,
                 apiKey: String,
                 model: String? = nil) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.missingAPIKey
        }
        let m = model?.isEmpty == false ? model! : provider.defaultModel
        switch provider {
        case .openAI: return try await openAI(text: text, apiKey: apiKey, model: m)
        case .claude: return try await claude(text: text, apiKey: apiKey, model: m)
        }
    }

    // MARK: - OpenAI

    private func openAI(text: String, apiKey: String, model: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 300,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": text]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Claude

    private func claude(text: String, apiKey: String, model: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": 300,
            "system":     systemPrompt,
            "messages":   [["role": "user", "content": text]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkHTTP(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIError.httpError(http.statusCode, msg)
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case missingAPIKey
    case badResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:          return "No AI API key set — add one in Settings."
        case .badResponse:            return "AI returned an unexpected response."
        case .httpError(let c, let m): return "AI HTTP \(c): \(m)"
        }
    }
}
