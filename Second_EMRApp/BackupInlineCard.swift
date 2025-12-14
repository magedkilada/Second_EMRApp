import SwiftUI

struct BackupInlineCard: View {
    @EnvironmentObject private var backup: BackupCenter
    let onBackupNow: () -> Void
    let onRestore: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Backup")
                        .font(.headline)
                    Spacer()
                    Text(backup.isICloudAvailable ? "iCloud" : "Local")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let d = backup.lastBackupDate {
                    Text("Last backup: \(d.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                }

                if let msg = backup.lastErrorMessage, !msg.isEmpty {
                    Text(msg).foregroundStyle(.red).font(.caption)
                }

                HStack {
                    Button("Backup now", action: onBackupNow)
                    Spacer()
                    Button("Restore", action: onRestore)
                }
            }
        }
    }
}
