//
//  Second_EMRAppApp.swift - COMPLETE with BackupCenter
//  Second_EMRApp
//

import SwiftUI

@main
struct Second_EMRAppApp: App {

    // MARK: - State Objects
    // These serve as the single source of truth for the entire app lifecycle
    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()
    @StateObject private var growthStore = GrowthStore.shared
    @StateObject private var backupCenter = BackupCenter()

    init() {
        print("🚀 APP LAUNCHED")
        // Diagnostic check for API key availability
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String {
            print("✅ API KEY LOADED")
        } else {
            print("⚠️ API KEY: NIL")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Inject objects into the environment so all subviews can access them
                .environmentObject(store)
                .environmentObject(physicians)
                .environmentObject(growthStore)
                .environmentObject(backupCenter)
                .task {
                    // 1. Load WHO Growth Data
                    growthStore.loadBundleJSON(named: [
                        "who_0_2_weightForAge_male",
                        "who_0_2_weightForAge_female",
                        "who_0_2_heightForAge_male",
                        "who_0_2_heightForAge_female",
                        "who_0_2_headCircForAge_male",
                        "who_0_2_headCircForAge_female"
                    ])
                    
                    // 2. Preload pediatric references
                    GrowthReferences.shared.preloadIfNeeded()
                    
                    // 3. WIRE BACKUP CENTER TO STORE
                    // This allows the store to trigger auto-backups during data saves
                    store.backupCenter = backupCenter
                }
        }
    }
}

