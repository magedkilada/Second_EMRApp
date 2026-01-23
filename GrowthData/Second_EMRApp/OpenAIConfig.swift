import Foundation

enum OpenAIConfig {
    static let model = "gpt-4o-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    static let apiKeyInfoPlistKey = "OPENAI_API_KEY"
}
