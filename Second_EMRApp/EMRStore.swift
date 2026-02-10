import Foundation
import Combine

@MainActor
final class EMRStore: ObservableObject {

    // MARK: - Published State

    @Published var patients: [Patient] = []
    @Published var notes: [RecordNote] = []
    @Published var attachments: [Attachment] = []
    
    // ✅ Consolidated naming to 'vitals' to match internal logic and external calls
    @Published public var vitals: [SmartVitalsEntry] = []

    @Published var selectedPatientID: UUID? = nil
    @Published var selectedNoteID: UUID? = nil

    @Published var lastModified: Date = Date()
    @Published var lastErrorMessage: String? = nil

    // MARK: - Computed Properties

    var selectedPatient: Patient? {
        guard let id = selectedPatientID else { return nil }
        return patients.first { $0.id == id && !$0.isDeleted }
    }

    // MARK: - Auto-backup integration

    /// Set this once in ContentView: store.backupCenter = backupCenter
    var backupCenter: BackupCenter? = nil
    var referencesStore: ReferencesStore? = nil

    // MARK: - Init

    init() {
        loadAll()

        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }

        // Register for iCloud remote changes
        let sync = iCloudSyncManager.shared
        sync.registerForChanges(filename: "patients.json") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let p = self.load([Patient].self, from: self.patientsURL) { self.patients = p }
            }
        }
        sync.registerForChanges(filename: "notes.json") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let n = self.load([RecordNote].self, from: self.notesURL) { self.notes = n }
            }
        }
        sync.registerForChanges(filename: "attachments.json") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let a = self.load([Attachment].self, from: self.attachmentsURL) { self.attachments = a }
            }
        }
        sync.registerForChanges(filename: "vitals.json") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let v = self.load([SmartVitalsEntry].self, from: self.vitalsURL) { self.vitals = v }
            }
        }
    }

    // MARK: - Public API (Patients)

    @discardableResult
    func addNewPatient() -> Patient {
        let p = Patient()
        patients.insert(p, at: 0)
        selectedPatientID = p.id
        savePatients()

        // Cloud sync
        SyncManager.shared.queuePatientChange(p, operation: .create)
        return p
    }

    func savePatient(_ patient: Patient) {
        let isNew = !patients.contains(where: { $0.id == patient.id })
        if let idx = patients.firstIndex(where: { $0.id == patient.id }) {
            patients[idx] = patient
        } else {
            patients.insert(patient, at: 0)
        }
        lastModified = Date()
        savePatients()

        // Cloud sync
        SyncManager.shared.queuePatientChange(patient, operation: isNew ? .create : .update)
    }

    func softDeletePatient(_ id: UUID) {
        guard let idx = patients.firstIndex(where: { $0.id == id }) else { return }
        patients[idx].isDeleted = true

        if selectedPatientID == id {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }

        lastModified = Date()
        savePatients()

        // Cloud sync
        SyncManager.shared.queuePatientChange(patients[idx], operation: .update)
    }

    func replaceAllPatients(with newPatients: [Patient]) {
        patients = newPatients
        selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        lastModified = Date()
        savePatients()
    }

    func replaceAllNotes(with newNotes: [RecordNote]) {
        notes = newNotes
        selectedNoteID = nil
        lastModified = Date()
        saveNotes()
    }

    func replaceAllVitals(with newVitals: [SmartVitalsEntry]) {
        vitals = newVitals
        lastModified = Date()
        saveVitals()
    }

    // MARK: - Public API (Notes)

    @discardableResult
    func addNote(_ note: RecordNote) -> RecordNote {
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        lastModified = Date()
        saveNotes()

        // Cloud sync
        SyncManager.shared.queueNoteChange(note, operation: .create)
        return note
    }

    func saveNote(_ note: RecordNote) {
        let isNew = !notes.contains(where: { $0.id == note.id })
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
        lastModified = Date()
        saveNotes()

        // Cloud sync
        SyncManager.shared.queueNoteChange(note, operation: isNew ? .create : .update)
    }
    

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id { selectedNoteID = notes.first?.id }
        lastModified = Date()
        saveNotes()

        // Cloud sync
        SyncManager.shared.queueChange(PendingChange(entityType: .note, entityId: id, operation: .delete))
    }

    // MARK: - Public API (Attachments)

    func addAttachment(_ attachment: Attachment) {
        attachments.insert(attachment, at: 0)
        lastModified = Date()
        saveAttachments()
    }

    func softDeleteAttachment(_ id: UUID) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[idx].isDeleted = true
        lastModified = Date()
        saveAttachments()
    }

    func setAttachments(_ newAttachments: [Attachment]) {
        attachments = newAttachments
        lastModified = Date()
        saveAttachments()
    }

    // MARK: - Merge (cross-device deduplication)

    /// Merge incoming patients, keeping the newer `updatedAt` for duplicates.
    func mergePatients(with incoming: [Patient]) -> (added: Int, updated: Int) {
        var existing = Dictionary(uniqueKeysWithValues: patients.map { ($0.id, $0) })
        var added = 0, updated = 0

        for item in incoming {
            if let current = existing[item.id] {
                if item.updatedAt > current.updatedAt {
                    existing[item.id] = item
                    updated += 1
                }
            } else {
                existing[item.id] = item
                added += 1
            }
        }

        patients = Array(existing.values).sorted { $0.createdAt > $1.createdAt }
        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
        lastModified = Date()
        savePatients()
        return (added, updated)
    }

    /// Merge incoming notes, keeping the newer `updatedAt` for duplicates.
    func mergeNotes(with incoming: [RecordNote]) -> (added: Int, updated: Int) {
        var existing = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var added = 0, updated = 0

        for item in incoming {
            if let current = existing[item.id] {
                if item.updatedAt > current.updatedAt {
                    existing[item.id] = item
                    updated += 1
                }
            } else {
                existing[item.id] = item
                added += 1
            }
        }

        notes = Array(existing.values).sorted { $0.createdAt > $1.createdAt }
        lastModified = Date()
        saveNotes()
        return (added, updated)
    }

    /// Merge incoming attachments by UUID (add if new).
    func mergeAttachments(with incoming: [Attachment]) -> Int {
        let existingIDs = Set(attachments.map { $0.id })
        let newItems = incoming.filter { !existingIDs.contains($0.id) }

        if !newItems.isEmpty {
            attachments.append(contentsOf: newItems)
            attachments.sort { $0.createdAt > $1.createdAt }
            lastModified = Date()
            saveAttachments()
        }
        return newItems.count
    }

    /// Merge incoming vitals by UUID (add if new).
    func mergeVitals(with incoming: [SmartVitalsEntry]) -> Int {
        let existingIDs = Set(vitals.map { $0.id })
        let newItems = incoming.filter { !existingIDs.contains($0.id) }

        if !newItems.isEmpty {
            vitals.append(contentsOf: newItems)
            vitals.sort { $0.recordedAt > $1.recordedAt }
            lastModified = Date()
            saveVitals()
        }
        return newItems.count
    }

    // MARK: - Persistence

    func forcePersistAll() {
        savePatients()
        saveNotes()
        saveAttachments()
        saveVitals()
    }

    private func loadAll() {
        patients = load([Patient].self, from: patientsURL) ?? []
        notes = load([RecordNote].self, from: notesURL) ?? []
        attachments = load([Attachment].self, from: attachmentsURL) ?? []
        if let v = load([SmartVitalsEntry].self, from: vitalsURL) {
            vitals = v
        }
    }

    public func savePatients() {
        save(patients, to: patientsURL)
        print("✅ savePatients wrote: \(patients.count) patients")
    }

    public func saveNotes() {
        save(notes, to: notesURL)
        maybeAutoBackup()
    }

    func saveVitals() {
        save(vitals, to: vitalsURL)
    }

    public func saveAttachments() {
        save(attachments, to: attachmentsURL)
        maybeAutoBackup()
    }

    // MARK: - Auto Backup Hook

    private func maybeAutoBackup() {
        guard let backupCenter = backupCenter else { return }

        guard let pw = AutoBackupKeychain.load(), !pw.isEmpty else { return }

        guard let refStore = referencesStore else { return }
        backupCenter.autoBackupIfNeeded(store: self, referencesStore: refStore, password: pw)
    }

    // MARK: - File URLs (iCloud-aware)

    private var patientsURL: URL { iCloudSyncManager.shared.url(for: "patients.json") }
    private var notesURL: URL { iCloudSyncManager.shared.url(for: "notes.json") }
    private var attachmentsURL: URL { iCloudSyncManager.shared.url(for: "attachments.json") }
    private var vitalsURL: URL { iCloudSyncManager.shared.url(for: "vitals.json") }

    // MARK: - JSON helpers

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ Load failed \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("❌ Save failed \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Vitals API

    public func vitalsForPatient(_ patientID: UUID) -> [SmartVitalsEntry] {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    public func addOrUpdateVitals(_ entry: SmartVitalsEntry, withinSeconds: TimeInterval = 180) {
        if let idx = vitals.enumerated()
            .filter({ $0.element.patientID == entry.patientID })
            .max(by: { $0.element.recordedAt < $1.element.recordedAt })?.offset {

            let last = vitals[idx]
            let dt = abs(last.recordedAt.timeIntervalSince(entry.recordedAt))

            if dt <= withinSeconds {
                var updated = entry
                updated.id = last.id
                vitals[idx] = updated
                lastModified = Date()
                saveVitals()

                // Cloud sync
                SyncManager.shared.queueVitalChange(updated, operation: .update)
                return
            }
        }

        vitals.insert(entry, at: 0)
        lastModified = Date()
        saveVitals()

        // Cloud sync
        SyncManager.shared.queueVitalChange(entry, operation: .create)
    }

    public func deleteVitals(_ id: UUID) {
        vitals.removeAll(where: { $0.id == id })
        lastModified = Date()
        saveVitals()

        // Cloud sync
        SyncManager.shared.queueChange(PendingChange(entityType: .vital, entityId: id, operation: .delete))
    }

    public func upsertVitals(_ entry: SmartVitalsEntry) {
        let isNew = !vitals.contains(where: { $0.id == entry.id })
        if let idx = vitals.firstIndex(where: { $0.id == entry.id }) {
            vitals[idx] = entry
        } else {
            vitals.insert(entry, at: 0)
        }
        lastModified = Date()
        saveVitals()

        // Cloud sync
        SyncManager.shared.queueVitalChange(entry, operation: isNew ? .create : .update)
    }
}


