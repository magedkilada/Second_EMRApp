//
//  Second_EMRAppApp.swift - COMPLETE with BackupCenter + Supabase Cloud Sync
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
    @StateObject private var referencesStore = ReferencesStore()
    @StateObject private var appointmentStore = AppointmentStore()
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var syncManager = SyncManager.shared

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
            RootView()
                // Inject objects into the environment so all subviews can access them
                .environmentObject(store)
                .environmentObject(physicians)
                .environmentObject(growthStore)
                .environmentObject(backupCenter)
                .environmentObject(referencesStore)
                .environmentObject(appointmentStore)
                .environmentObject(supabaseManager)
                .environmentObject(syncManager)
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

                    // 3. WIRE BACKUP CENTER + REFERENCES TO STORE
                    // This allows the store to trigger auto-backups during data saves
                    store.backupCenter = backupCenter
                    store.referencesStore = referencesStore

                    // 4. Start iCloud sync monitoring
                    iCloudSyncManager.shared.startMonitoring()

                    // 5. Check Supabase session and pull latest data
                    await supabaseManager.checkSession()

                    // 6. Auto-sync: pull latest data from Supabase after login
                    if supabaseManager.isAuthenticated {
                        await syncManager.performFullSync(
                            emrStore: store,
                            appointmentStore: appointmentStore,
                            physiciansStore: physicians,
                            referencesStore: referencesStore
                        )
                    }
                }
        }
    }
}

// MARK: - Root View (Auth Check)

struct RootView: View {
    @EnvironmentObject var supabaseManager: SupabaseManager

    var body: some View {
        Group {
            if SupabaseConfig.isConfigured {
                if supabaseManager.isAuthenticated {
                    ContentView()
                } else {
                    AuthView()
                }
            } else {
                // Supabase not configured - run in offline mode
                ContentView()
            }
        }
    }
}

