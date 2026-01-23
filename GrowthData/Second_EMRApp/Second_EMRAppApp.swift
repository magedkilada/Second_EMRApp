import SwiftUI

@main
struct Second_EMRAppApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()
    @StateObject private var growthStore = GrowthStore.shared

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
                .environmentObject(growthStore)
                .task {
                    // ✅ Load only the JSON files that actually exist in your bundle
                    growthStore.loadBundleJSON(named: [
                        "who_0_2_weightForAge_male",
                        "who_0_2_weightForAge_female",
                        "who_0_2_heightForAge_male",
                        "who_0_2_heightForAge_female",
                        "who_0_2_headCircForAge_male",
                        "who_0_2_headCircForAge_female"
                    ])
                }
        }
    }
}
