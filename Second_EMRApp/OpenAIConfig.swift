import Foundation

enum OpenAIConfig {
    static let model = "gpt-4o-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let apiKeyInfoPlistKey = "OPENAI_API_KEY"

    static var apiKey: String {
        // UserDefaults first (in-app entry wins), then Info.plist fallback
        if let key = UserDefaults.standard.string(forKey: "OPENAI_API_KEY"),
           isValidKey(key) {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: apiKeyInfoPlistKey) as? String,
           isValidKey(key) {
            return key
        }
        return ""
    }

    static var isConfigured: Bool {
        !apiKey.isEmpty
    }

    private static func isValidKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("$(") { return false }
        if trimmed.uppercased().hasPrefix("YOUR_") { return false }
        return true
    }
}
