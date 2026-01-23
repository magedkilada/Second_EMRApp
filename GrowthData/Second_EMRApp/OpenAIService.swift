import Foundation

final class OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    // Reads the key from Info.plist (which you already confirmed prints correctly)
    private var apiKey: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One-shot text generation (no tools, no streaming)
    func generate(
        instructions: String,
        input: String,
        maxOutputTokens: Int = 1200,
        temperature: Double = 0.2
    ) async throws -> String {

        guard !apiKey.isEmpty, !apiKey.contains("$(") else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY in app Info settings."
            ])
        }

        var req = URLRequest(url: OpenAIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OARequest(
            model: OpenAIConfig.model,
            input: input,
            instructions: instructions,
            max_output_tokens: maxOutputTokens,
            temperature: temperature,
            store: false
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI API error: \(raw)"
            ])
        }

        let decoded = try JSONDecoder().decode(OAResponse.self, from: data)

        if let out = decoded.output_text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty {
            return out
        }

        if let out = decoded.extractTextBestEffort(), !out.isEmpty {
            return out
        }

        return "No response."
    }
}

// MARK: - Models

private struct OARequest: Encodable {
    let model: String
    let input: String
    let instructions: String
    let max_output_tokens: Int
    let temperature: Double
    let store: Bool
}

private struct OAResponse: Decodable {
    let output_text: String?
    let output: [OutputItem]?

    struct OutputItem: Decodable {
        let type: String?
        let content: [ContentPart]?

        struct ContentPart: Decodable {
            let type: String?
            let text: String?
        }
    }

    func extractTextBestEffort() -> String? {
        guard let output else { return nil }
        var chunks: [String] = []
        for item in output {
            for part in item.content ?? [] {
                if let t = part.text, !t.isEmpty { chunks.append(t) }
            }
        }
        let joined = chunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
