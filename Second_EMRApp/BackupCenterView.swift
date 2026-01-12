import SwiftUI

struct BackupCenterView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Backup & Restore",
                systemImage: "externaldrive",
                description: Text("Backup center not yet connected.")
            )
            .navigationTitle("Backup & Restore")
        }
    }
}
