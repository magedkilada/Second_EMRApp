import SwiftUI

@main
struct Second_EMRAppApp: App {

    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(physicians)
        }
    }
}
