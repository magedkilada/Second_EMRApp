import Foundation

enum ClaudeConfig {
    static let model = "claude-sonnet-4-20250514"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    static var apiKey: String {
        // First try Info.plist, then UserDefaults
        if let key = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
           !key.isEmpty, !key.contains("$(") {
            return key
        }
        return UserDefaults.standard.string(forKey: "ANTHROPIC_API_KEY") ?? ""
    }

    static var isConfigured: Bool {
        !apiKey.isEmpty
    }
}

final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    func generate(
        system: String,
        userMessage: String,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {

        let key = ClaudeConfig.apiKey
        guard !key.isEmpty else {
            throw NSError(domain: "Claude", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Missing Anthropic API key. Go to Settings to configure."
            ])
        }

        var req = URLRequest(url: ClaudeConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(ClaudeConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": ClaudeConfig.model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "system": system,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "Claude", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Claude API error: \(raw)"
            ])
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let text = decoded.content
            .compactMap { $0.type == "text" ? $0.text : nil }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? "No response." : text
    }
}

// MARK: - Response Models

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
