import SwiftUI

@main
struct Second_EMRAppApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()

    init() {
        print("🚀 APP LAUNCHED")
        print("API KEY:",
              Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") ?? "NIL")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(physicians)
        }
    }
}
