import Foundation

struct OpenAIWhisperTranscriber {

    enum TranscriberError: Error, LocalizedError {
        case missingAPIKey
        case badResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "OpenAI API key not set. Tap AI > key icon to configure."
            case .badResponse: return "Bad response from transcription service."
            case .server(let msg): return msg
            }
        }
    }

    private let model: String

    init(model: String = "whisper-1") {
        self.model = model
    }

    func transcribe(fileURL: URL) async throws -> String {

        // Use centralized key from OpenAIConfig (checks UserDefaults first, then Info.plist)
        let key = OpenAIConfig.apiKey
        guard !key.isEmpty else {
            throw TranscriberError.missingAPIKey
        }

        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)

        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        // model
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        // optional: language hint (helps accuracy sometimes)
        // append("--\(boundary)\r\n")
        // append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        // append("en\r\n")

        // file
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriberError.badResponse }

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranscriberError.server(msg)
        }

        struct Resp: Decodable { let text: String? }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
