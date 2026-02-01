import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EMRStore
    @EnvironmentObject var backupCenter: BackupCenter
    @EnvironmentObject var referencesStore: ReferencesStore
    @EnvironmentObject var appointmentStore: AppointmentStore
    @EnvironmentObject var physiciansStore: PhysiciansStore

    @State private var shareURL: URL? = nil
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPasswordSetup = false
    @State private var hasKeychainPassword = false

    @State private var showRestoreFilePicker = false
    @State private var restorePassword: String = ""
    @State private var showRestorePasswordPrompt = false
    @State private var pendingRestoreURL: URL? = nil

    @State private var showRestoreConfirm = false
    @State private var showRestoreSuccess = false
    @State private var showBackupSuccess = false

    // Merge
    @State private var showMergeFilePicker = false
    @State private var mergePassword: String = ""
    @State private var showMergePasswordPrompt = false
    @State private var pendingMergeURL: URL? = nil
    @State private var showMergeSuccess = false
    @State private var mergeResultSummary: String = ""

    @State private var backupFiles: [BackupFileInfo] = []
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteURL: URL? = nil

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                passwordSection
                manualBackupSection
                autoBackupSection
                mergeSection
                restoreSection
                existingBackupsSection
            }
            .navigationTitle("Backup & Restore")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                hasKeychainPassword = AutoBackupKeychain.load() != nil
                backupFiles = backupCenter.listBackups()
            }
            .fileImporter(
                isPresented: $showRestoreFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "emrbackup") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingRestoreURL = url
                    restorePassword = ""
                    showRestorePasswordPrompt = true
                }
            }
            .alert("Enter Backup Password", isPresented: $showRestorePasswordPrompt) {
                SecureField("Password", text: $restorePassword)
                Button("Restore", role: .destructive) {
                    showRestoreConfirm = true
                }
                Button("Cancel", role: .cancel) {
                    pendingRestoreURL = nil
                    restorePassword = ""
                }
            } message: {
                Text("Enter the password used when this backup was created.")
            }
            .alert("Restore Will Replace All Data", isPresented: $showRestoreConfirm) {
                Button("Replace All Data", role: .destructive) {
                    performRestore()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace ALL current patients, notes, vitals, and attachments with the backup data. This cannot be undone.")
            }
            .alert("Restore Complete", isPresented: $showRestoreSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("All data has been restored from backup. The app will reflect the restored data.")
            }
            .alert("Backup Created", isPresented: $showBackupSuccess) {
                Button("OK") {}
            } message: {
                Text("Encrypted backup saved locally. Use the share button to export it to iCloud Drive or another cloud storage.")
            }
            #if os(iOS)
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            #endif
            .onChange(of: shareURL) { _, newURL in
                #if os(macOS)
                if let url = newURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    shareURL = nil
                }
                #endif
            }
            .fileImporter(
                isPresented: $showMergeFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "emrbackup") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    pendingMergeURL = url
                    mergePassword = ""
                    showMergePasswordPrompt = true
                }
            }
            .alert("Enter Backup Password", isPresented: $showMergePasswordPrompt) {
                SecureField("Password", text: $mergePassword)
                Button("Merge") {
                    performMerge()
                }
                Button("Cancel", role: .cancel) {
                    pendingMergeURL = nil
                    mergePassword = ""
                }
            } message: {
                Text("Enter the password used when this backup was created. Data will be merged — nothing will be deleted.")
            }
            .alert("Merge Complete", isPresented: $showMergeSuccess) {
                Button("OK") {}
            } message: {
                Text(mergeResultSummary)
            }
            .alert("Delete Backup?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let url = pendingDeleteURL {
                        backupCenter.deleteBackup(url)
                        backupFiles = backupCenter.listBackups()
                    }
                    pendingDeleteURL = nil
                }
                Button("Cancel", role: .cancel) { pendingDeleteURL = nil }
            } message: {
                Text("This backup file will be permanently deleted.")
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Local + Encrypted Export")
                    .font(.subheadline)
            }

            if let date = backupCenter.lastBackupDate {
                HStack {
                    Image(systemName: "clock.fill").foregroundStyle(.green)
                    Text("Last Backup: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                }
            }

            if !backupCenter.lastError.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(backupCenter.lastError).font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Data is stored locally on device. Use \"Export to iCloud Drive\" to manually sync an encrypted backup across devices.")
        }
    }

    private var passwordSection: some View {
        Section {
            if hasKeychainPassword {
                HStack {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Encryption password is set")
                    Spacer()
                    Button("Change") { showPasswordSetup = true }
                        .font(.subheadline)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                    Text("No encryption password set")
                }
                Button("Set Password") { showPasswordSetup = true }
            }

            if showPasswordSetup {
                SecureField("New Password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)

                if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match").font(.caption).foregroundStyle(.red)
                }

                Button("Save Password to Keychain") {
                    savePassword()
                }
                .disabled(password.isEmpty || password != confirmPassword || password.count < 4)
            }
        } header: {
            Text("Encryption Password")
        } footer: {
            Text("Password is stored securely in the device Keychain. You will need this password to restore backups.")
        }
    }

    private var manualBackupSection: some View {
        Section {
            Button {
                createManualBackup()
            } label: {
                HStack {
                    Image(systemName: "externaldrive.badge.plus")
                    Text("Create Backup Now")
                    Spacer()
                    if backupCenter.isProcessing {
                        ProgressView()
                    }
                }
            }
            .disabled(!hasKeychainPassword || backupCenter.isProcessing)

            Button {
                createAndShare()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Create & Export to iCloud Drive")
                }
            }
            .disabled(!hasKeychainPassword || backupCenter.isProcessing)
        } header: {
            Text("Manual Backup")
        } footer: {
            if !hasKeychainPassword {
                Text("Set an encryption password first.")
            } else {
                Text("\"Export to iCloud Drive\" creates a backup and opens the share sheet so you can save it to iCloud Drive, AirDrop, or any cloud storage.")
            }
        }
    }

    private var autoBackupSection: some View {
        Section {
            Toggle("Auto-Backup", isOn: $backupCenter.autoBackupEnabled)
                .disabled(!hasKeychainPassword)
        } header: {
            Text("Automatic Backup")
        } footer: {
            Text("When enabled, the app automatically creates an encrypted backup after data changes (at most once per hour).")
        }
    }

    private var mergeSection: some View {
        Section {
            Button {
                showMergeFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Merge from Backup...")
                    Spacer()
                    if backupCenter.isProcessing {
                        ProgressView()
                    }
                }
            }
            .disabled(backupCenter.isProcessing)
        } header: {
            Text("Merge (Cross-Device Sync)")
        } footer: {
            Text("Import a backup from another device. New records are added, duplicates are updated to the newest version. Nothing is deleted.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                showRestoreFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Restore from File...")
                }
            }

            if let date = backupCenter.lastRestoreDate {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Last Restore: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                }
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Restoring will REPLACE all current data with the backup contents.")
        }
    }

    private var existingBackupsSection: some View {
        Section {
            if backupFiles.isEmpty {
                Text("No backup files found.").foregroundStyle(.secondary)
            } else {
                ForEach(backupFiles) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.filename)
                                .font(.caption).bold()
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(file.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Text(file.formattedSize)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            shareURL = file.url
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button {
                            pendingRestoreURL = file.url
                            restorePassword = ""
                            showRestorePasswordPrompt = true
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button {
                            pendingDeleteURL = file.url
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            HStack {
                Text("Saved Backups")
                Spacer()
                Button {
                    backupFiles = backupCenter.listBackups()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func savePassword() {
        do {
            try AutoBackupKeychain.save(password)
            hasKeychainPassword = true
            showPasswordSetup = false
            password = ""
            confirmPassword = ""
        } catch {
            backupCenter.lastError = "Failed to save password: \(error.localizedDescription)"
        }
    }

    private func createAndShare() {
        guard let pw = AutoBackupKeychain.load() else { return }
        backupCenter.createBackup(store: store, referencesStore: referencesStore, password: pw,
                                  appointmentStore: appointmentStore, physiciansStore: physiciansStore)
        if backupCenter.lastError.isEmpty {
            backupFiles = backupCenter.listBackups()
            shareURL = backupCenter.lastCreatedBackupURL
        }
    }

    private func createManualBackup() {
        guard let pw = AutoBackupKeychain.load() else { return }
        backupCenter.createBackup(store: store, referencesStore: referencesStore, password: pw,
                                  appointmentStore: appointmentStore, physiciansStore: physiciansStore)
        if backupCenter.lastError.isEmpty {
            showBackupSuccess = true
            backupFiles = backupCenter.listBackups()
        }
    }

    private func performMerge() {
        guard let url = pendingMergeURL else { return }
        if let result = backupCenter.mergeFromFile(url, password: mergePassword, store: store, referencesStore: referencesStore,
                                                   appointmentStore: appointmentStore, physiciansStore: physiciansStore) {
            mergeResultSummary = result.summary
            showMergeSuccess = true
        }
        pendingMergeURL = nil
        mergePassword = ""
    }

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        let success = backupCenter.restoreFromFile(url, password: restorePassword, store: store, referencesStore: referencesStore,
                                                   appointmentStore: appointmentStore, physiciansStore: physiciansStore)
        if success {
            showRestoreSuccess = true
        }
        pendingRestoreURL = nil
        restorePassword = ""
    }
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
