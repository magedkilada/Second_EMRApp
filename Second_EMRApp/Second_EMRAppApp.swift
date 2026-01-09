import SwiftUI

@main
struct Second_EMRAppApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()

    // ✅ Add this
    @State private var globalSearchQuery: String = ""

    var body: some Scene {
        WindowGroup {
            ContentView(query: $globalSearchQuery)
                .environmentObject(store)
                .environmentObject(physicians)
        }
    }
}
