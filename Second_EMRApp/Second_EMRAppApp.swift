import SwiftUI

@main
struct Second_EMRAppApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()

    init() {
        print("🚀 APP LAUNCHED")
        let hasKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?.isEmpty == false
        print("OPENAI_API_KEY present:", hasKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(physicians)
        }
    }
}
