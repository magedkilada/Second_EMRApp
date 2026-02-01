//
//  EEGAnalysisService.swift
//  Second_EMRApp
//

import Foundation

enum EEGServerConfig {
    static let defaultURL = "http://localhost:5050"

    static var baseURL: String {
        if let url = UserDefaults.standard.string(forKey: "EEG_SERVER_URL"),
           !url.isEmpty {
            return url
        }
        return defaultURL
    }
}

struct EEGAnalysisService {

    enum ServiceError: Error, LocalizedError {
        case serverUnavailable
        case badResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .serverUnavailable:
                return "EEG Server is not reachable. Make sure the server is running on your Mac (python3 eeg_server.py)."
            case .badResponse:
                return "Unexpected response from EEG server."
            case .server(let msg):
                return "EEG Server error: \(msg)"
            }
        }
    }

    func analyze(fileURL: URL, prompt: String? = nil) async throws -> String {
        let base = EEGServerConfig.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: "\(base)/analyze") else {
            throw ServiceError.serverUnavailable
        }

        let fileData = try Data(contentsOf: fileURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120 // EEG analysis can take time

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        // File field
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        // Optional prompt field
        if let prompt = prompt, !prompt.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            append("\(prompt)\r\n")
        }

        // Closing boundary
        append("--\(boundary)--\r\n")

        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.serverUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse
        }

        struct EEGResponse: Decodable {
            let report: String?
            let error: String?
        }

        let decoded = try JSONDecoder().decode(EEGResponse.self, from: data)

        if let error = decoded.error {
            throw ServiceError.server(error)
        }

        guard (200...299).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ServiceError.server(raw)
        }

        return decoded.report ?? "No report generated."
    }

    /// Check if the server is reachable.
    func checkHealth() async -> Bool {
        let base = EEGServerConfig.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/health") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
