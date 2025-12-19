import SwiftUI
import UniformTypeIdentifiers

struct BackupInlineCard: View {
    @EnvironmentObject private var backup: BackupCenter
    @EnvironmentObject private var store: EMRStore

    @State private var showExport = false
    @State private var exportDoc: BackupFileDocument?

    @State private var showImportPicker = false
    @State private var importedData: Data?

    @State private var askExportPassword = false
    @State private var exportPassword = ""
    @State private var exportPassword2 = ""

    @State private var askImportPassword = false
    @State private var importPassword = ""

    @State private var showAutoBackupSettings = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {

                HStack {
                    Text("Backup").font(.headline)
                    Spacer()
                    Text("Encrypted (Password)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let date = backup.lastBackupDate {
                    Text("Last backup: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No backups yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Export") { askExportPassword = true }
                    Button("Import") { showImportPicker = true }

                    Spacer()

                    Button("Auto-backup") { showAutoBackupSettings = true }
                        .buttonStyle(.bordered)
                }

                if let msg = backup.lastErrorMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }

        // Export flow
        .alert("Export password", isPresented: $askExportPassword) {
            SecureField("Password", text: $exportPassword)
            SecureField("Confirm", text: $exportPassword2)
            Button("Cancel", role: .cancel) { resetExport() }
            Button("Export") {
                guard !exportPassword.isEmpty, exportPassword == exportPassword2 else {
                    backup.lastErrorMessage = "Passwords do not match."
                    return
                }
                exportDoc = backup.makeEncryptedBackup(store: store, password: exportPassword)
                showExport = (exportDoc != nil)
            }
        } message: {
            Text("Choose a password. You’ll need the same password to import on another device.")
        }
        .fileExporter(
            isPresented: $showExport,
            document: exportDoc,
            contentType: .emrEncryptedBackup,
            defaultFilename: "NeurosurgeryEMR.backup"
        ) { _ in
            resetExport()
        }

        // Import picker
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.emrEncryptedBackup, .data]
        ) { result in
            do {
                let url = try result.get()
                let needs = url.startAccessingSecurityScopedResource()
                defer { if needs { url.stopAccessingSecurityScopedResource() } }
                importedData = try Data(contentsOf: url)
                askImportPassword = true
            } catch {
                backup.lastErrorMessage = "Import pick failed: \(error.localizedDescription)"
            }
        }

        // Import password prompt
        .alert("Import password", isPresented: $askImportPassword) {
            SecureField("Password", text: $importPassword)
            Button("Cancel", role: .cancel) { resetImport() }
            Button("Import") {
                guard let data = importedData else { return }
                backup.restoreEncryptedBackup(into: store, fileData: data, password: importPassword)
                resetImport()
            }
        } message: {
            Text("Enter the password used when exporting this backup.")
        }

        // ✅ Auto-backup settings sheet (ADD THIS)
        .sheet(isPresented: $showAutoBackupSettings) {
            NavigationStack {
                AutoBackupSettingsView()
            }
        }
    }

    private func resetExport() {
        exportPassword = ""
        exportPassword2 = ""
        exportDoc = nil
    }

    private func resetImport() {
        importPassword = ""
        importedData = nil
    }
}
