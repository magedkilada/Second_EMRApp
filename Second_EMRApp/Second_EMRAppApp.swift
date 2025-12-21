import SwiftUI
@main
struct Second_EMRAppApp: App {
    init() {
        print("🚀 APP LAUNCHED")
        print("API KEY:",
              Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") ?? "NIL")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    // other fields…
}
