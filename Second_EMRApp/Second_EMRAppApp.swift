import SwiftUI

@main
struct Second_EMRApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var backupCenter = BackupCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(backupCenter)
        }
    }
}
struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    // other fields…
}
