import SwiftUI

struct AutoBackupSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirm = ""

    @State private var statusText: String?
    @State private var isError = false

    private var hasSaved: Bool {
        AutoBackupKeychain.load() != nil
    }

    private var canSave: Bool {
        !password.isEmpty && password == confirm && password.count >= 6
    }

    var body: some View {
        SwiftUI.Form {
            Section("Auto-backup Password (Device Only)") {
                SecureField("Password", text: $password)
                SecureField("Confirm", text: $confirm)

                Text("Tip: Use a long passphrase you can also write down as a fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save to Keychain") {
                    do {
                        try AutoBackupKeychain.save(password)
                        statusText = "Saved. Auto-backup is now available on this device."
                        isError = false
                        password = ""
                        confirm = ""
                    } catch {
                        statusText = error.localizedDescription
                        isError = true
                    }
                }
                .disabled(!canSave)

                Button("Remove Saved Password", role: .destructive) {
                    do {
                        try AutoBackupKeychain.delete()
                        statusText = "Removed saved password."
                        isError = false
                    } catch {
                        statusText = error.localizedDescription
                        isError = true
                    }
                }
                .disabled(!hasSaved)
            }

            if let msg = statusText {
                Section {
                    Text(msg)
                        .foregroundStyle(isError ? .red : .secondary)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Auto-backup")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
