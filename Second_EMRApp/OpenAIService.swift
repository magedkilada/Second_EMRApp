

import Foundation

final class OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    // Uses the centralized key from OpenAIConfig
    private var apiKey: String {
        OpenAIConfig.apiKey
    }

    /// One-shot text generation via Chat Completions API
    func generate(
        instructions: String,
        input: String,
        maxOutputTokens: Int = 1200,
        temperature: Double = 0.2
    ) async throws -> String {

        guard !apiKey.isEmpty, !apiKey.contains("$(") else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY. Tap the key icon to configure."
            ])
        }

        var req = URLRequest(url: OpenAIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": OpenAIConfig.model,
            "max_tokens": maxOutputTokens,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": input]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI API error: \(raw)"
            ])
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        if let text = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return "No response."
    }

    // MARK: - Vision (image analysis)

    func generateWithImages(
        instructions: String,
        input: String,
        images: [(data: Data, mediaType: String)],
        maxOutputTokens: Int = 4096,
        temperature: Double = 0.2
    ) async throws -> String {

        guard !apiKey.isEmpty, !apiKey.contains("$(") else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY."
            ])
        }

        var req = URLRequest(url: OpenAIConfig.endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build content array: images as data URIs, then text
        var contentParts: [[String: Any]] = []
        for img in images {
            let dataURI = "data:\(img.mediaType);base64,\(img.data.base64EncodedString())"
            contentParts.append([
                "type": "image_url",
                "image_url": ["url": dataURI]
            ])
        }
        contentParts.append(["type": "text", "text": input])

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": maxOutputTokens,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": contentParts]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAI", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI API error: \(raw)"
            ])
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        if let text = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        return "No response."
    }
}

// MARK: - Chat Completions Response Models

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}
