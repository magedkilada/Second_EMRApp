//
//  BackupCenter.swift
//  Second_EMRApp
//

import Foundation
import Combine

@MainActor
final class BackupCenter: ObservableObject {

    @Published var lastBackupDate: Date? = nil
    @Published var lastCreatedBackupURL: URL? = nil

    @Published var isProcessing: Bool = false
    @Published var lastError: String = ""
    @Published var lastRestoreDate: Date? = nil

    @Published var autoBackupEnabled: Bool = false {
        didSet { UserDefaults.standard.set(autoBackupEnabled, forKey: "EMR_AUTOBACKUP_ENABLED") }
    }

    init() {
        autoBackupEnabled = UserDefaults.standard.bool(forKey: "EMR_AUTOBACKUP_ENABLED")
        if let d = UserDefaults.standard.object(forKey: "EMR_LAST_BACKUP_DATE") as? Date {
            lastBackupDate = d
        }
    }

    // MARK: - Backup Directory (local only)

    static var backupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Create Backup

    func createBackup(store: EMRStore, referencesStore: ReferencesStore, password: String,
                      appointmentStore: AppointmentStore? = nil, physiciansStore: PhysiciansStore? = nil) {
        guard !isProcessing else { return }
        guard !password.isEmpty else { lastError = "Password is required."; return }
        isProcessing = true
        lastError = ""

        do {
            let payload = BackupPayload(
                patients: store.patients,
                notes: store.notes,
                attachments: store.attachments,
                vitals: store.vitals,
                references: referencesStore.items,
                appointments: appointmentStore?.appointments ?? [],
                physicians: physiciansStore?.physicians ?? []
            )
            let jsonData = try JSONEncoder().encode(payload)
            let encrypted = try BackupCrypto.encrypt(jsonData, password: password)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let filename = "EMRBackup_\(formatter.string(from: Date())).emrbackup"
            let fileURL = Self.backupDirectory.appendingPathComponent(filename)
            try encrypted.write(to: fileURL, options: .atomic)

            recordBackup(url: fileURL)
        } catch {
            lastError = error.localizedDescription
        }

        isProcessing = false
    }

    // MARK: - Restore from File

    func restoreFromFile(_ fileURL: URL, password: String, store: EMRStore, referencesStore: ReferencesStore,
                         appointmentStore: AppointmentStore? = nil, physiciansStore: PhysiciansStore? = nil) -> Bool {
        guard !isProcessing else { return false }
        guard !password.isEmpty else { lastError = "Password is required."; return false }
        isProcessing = true
        lastError = ""

        defer { isProcessing = false }

        do {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

            let encryptedData = try Data(contentsOf: fileURL)
            let decryptedData = try BackupCrypto.decrypt(encryptedData, password: password)
            let payload = try JSONDecoder().decode(BackupPayload.self, from: decryptedData)

            // Apply the restored data
            store.replaceAllPatients(with: payload.patients)
            store.replaceAllNotes(with: payload.notes)
            store.setAttachments(payload.attachments)
            store.replaceAllVitals(with: payload.vitals)
            referencesStore.replaceAll(with: payload.references)
            if !payload.appointments.isEmpty {
                appointmentStore?.replaceAll(with: payload.appointments)
            }
            if !payload.physicians.isEmpty {
                physiciansStore?.replaceAll(with: payload.physicians)
            }

            lastRestoreDate = Date()
            return true
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Merge from File (cross-device deduplication)

    struct MergeResult {
        var patientsAdded: Int = 0
        var patientsUpdated: Int = 0
        var notesAdded: Int = 0
        var notesUpdated: Int = 0
        var attachmentsAdded: Int = 0
        var vitalsAdded: Int = 0
        var referencesAdded: Int = 0
        var appointmentsAdded: Int = 0
        var physiciansAdded: Int = 0

        var summary: String {
            var parts: [String] = []
            if patientsAdded > 0 { parts.append("\(patientsAdded) new patient\(patientsAdded == 1 ? "" : "s")") }
            if patientsUpdated > 0 { parts.append("\(patientsUpdated) patient\(patientsUpdated == 1 ? "" : "s") updated") }
            if notesAdded > 0 { parts.append("\(notesAdded) new note\(notesAdded == 1 ? "" : "s")") }
            if notesUpdated > 0 { parts.append("\(notesUpdated) note\(notesUpdated == 1 ? "" : "s") updated") }
            if attachmentsAdded > 0 { parts.append("\(attachmentsAdded) new attachment\(attachmentsAdded == 1 ? "" : "s")") }
            if vitalsAdded > 0 { parts.append("\(vitalsAdded) new vitals entr\(vitalsAdded == 1 ? "y" : "ies")") }
            if referencesAdded > 0 { parts.append("\(referencesAdded) new reference\(referencesAdded == 1 ? "" : "s")") }
            if appointmentsAdded > 0 { parts.append("\(appointmentsAdded) new appointment\(appointmentsAdded == 1 ? "" : "s")") }
            if physiciansAdded > 0 { parts.append("\(physiciansAdded) new physician\(physiciansAdded == 1 ? "" : "s")") }

            if parts.isEmpty { return "No new data found — everything was already up to date." }
            return parts.joined(separator: ", ") + "."
        }
    }

    func mergeFromFile(_ fileURL: URL, password: String, store: EMRStore, referencesStore: ReferencesStore,
                       appointmentStore: AppointmentStore? = nil, physiciansStore: PhysiciansStore? = nil) -> MergeResult? {
        guard !isProcessing else { return nil }
        guard !password.isEmpty else { lastError = "Password is required."; return nil }
        isProcessing = true
        lastError = ""

        defer { isProcessing = false }

        do {
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

            let encryptedData = try Data(contentsOf: fileURL)
            let decryptedData = try BackupCrypto.decrypt(encryptedData, password: password)
            let payload = try JSONDecoder().decode(BackupPayload.self, from: decryptedData)

            var result = MergeResult()

            let patientMerge = store.mergePatients(with: payload.patients)
            result.patientsAdded = patientMerge.added
            result.patientsUpdated = patientMerge.updated

            let noteMerge = store.mergeNotes(with: payload.notes)
            result.notesAdded = noteMerge.added
            result.notesUpdated = noteMerge.updated

            result.attachmentsAdded = store.mergeAttachments(with: payload.attachments)
            result.vitalsAdded = store.mergeVitals(with: payload.vitals)
            result.referencesAdded = referencesStore.mergeItems(with: payload.references)
            if let apptStore = appointmentStore {
                result.appointmentsAdded = apptStore.mergeAppointments(with: payload.appointments)
            }
            if let physStore = physiciansStore {
                result.physiciansAdded = physStore.mergePhysicians(with: payload.physicians)
            }

            return result
        } catch {
            lastError = "Merge failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - List Available Backups

    func listBackups() -> [BackupFileInfo] {
        let dir = Self.backupDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "emrbackup" }
            .compactMap { url -> BackupFileInfo? in
                let vals = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return BackupFileInfo(
                    url: url,
                    filename: url.lastPathComponent,
                    createdAt: vals?.creationDate ?? Date.distantPast,
                    fileSize: vals?.fileSize ?? 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteBackup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Auto-Backup

    func autoBackupIfNeeded(store: EMRStore, referencesStore: ReferencesStore, password: String,
                            appointmentStore: AppointmentStore? = nil, physiciansStore: PhysiciansStore? = nil) {
        guard autoBackupEnabled, !isProcessing, !password.isEmpty else { return }

        // Throttle: only auto-backup once per hour
        if let last = lastBackupDate, Date().timeIntervalSince(last) < 3600 { return }

        createBackup(store: store, referencesStore: referencesStore, password: password,
                     appointmentStore: appointmentStore, physiciansStore: physiciansStore)
    }

    // MARK: - Helpers

    func recordBackup(url: URL) {
        lastBackupDate = Date()
        lastCreatedBackupURL = url
        UserDefaults.standard.set(lastBackupDate, forKey: "EMR_LAST_BACKUP_DATE")
    }
}

// MARK: - Backup File Info

struct BackupFileInfo: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let createdAt: Date
    let fileSize: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
