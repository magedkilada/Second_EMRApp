import SwiftUI


struct BackupInlineCard: View {

    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var backup: BackupCenter
    

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Backup & Restore", systemImage: "lock.shield")
                        .font(.headline)
                    Spacer()
                    if let d = backup.lastBackupDate {
                        Text("Last: \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Keep your existing buttons/actions here (export/import UI etc.)
                Text("Secure clinical data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
