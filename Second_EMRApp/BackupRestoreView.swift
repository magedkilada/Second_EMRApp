import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: EMRStore
    @EnvironmentObject var backupCenter: BackupCenter

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
                Text("Encrypted backup saved successfully.\(BackupCenter.isICloudAvailable ? " It will sync to iCloud." : "")")
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
                Image(systemName: BackupCenter.isICloudAvailable ? "icloud.fill" : "internaldrive.fill")
                    .foregroundStyle(BackupCenter.isICloudAvailable ? .blue : .orange)
                Text(BackupCenter.isICloudAvailable ? "iCloud Available" : "Local Storage Only")
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
        } header: {
            Text("Manual Backup")
        } footer: {
            if !hasKeychainPassword {
                Text("Set an encryption password first.")
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

    private func createManualBackup() {
        guard let pw = AutoBackupKeychain.load() else { return }
        backupCenter.createBackup(store: store, password: pw)
        if backupCenter.lastError.isEmpty {
            showBackupSuccess = true
            backupFiles = backupCenter.listBackups()
        }
    }

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        let success = backupCenter.restoreFromFile(url, password: restorePassword, store: store)
        if success {
            showRestoreSuccess = true
        }
        pendingRestoreURL = nil
        restorePassword = ""
    }
}
