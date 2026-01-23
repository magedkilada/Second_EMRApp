import Foundation
import Combine

@MainActor
final class EMRStore: ObservableObject {

    // MARK: - Published State

    @Published var patients: [Patient] = []
    @Published var notes: [RecordNote] = []
    @Published var attachments: [Attachment] = []

    @Published var selectedPatientID: UUID? = nil
    @Published var selectedNoteID: UUID? = nil

    @Published var lastModified: Date = Date()
    @Published var lastErrorMessage: String? = nil
    
    @Published public var vitals: [SmartVitalsEntry] = []

    // MARK: - Auto-backup integration (wired from ContentView)

    /// Set this once in ContentView:
    /// store.backupCenter = backupCenter
    var backupCenter: BackupCenter? = nil

    // MARK: - Init

    init() {
        loadAll()

        print("🧠 Patients loaded from disk:", patients.count)
        print("🧠 Patient IDs:", patients.map { "\($0.id) deleted=\($0.isDeleted)" })

        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - Public API (Patients)

    @discardableResult
    func addNewPatient() -> Patient {
        var p = Patient()
        p.isDeleted = false
        patients.insert(p, at: 0)
        selectedPatientID = p.id
        savePatients()
        return p
    }

    func savePatient(_ patient: Patient) {
        if let idx = patients.firstIndex(where: { $0.id == patient.id }) {
            patients[idx] = patient
        } else {
            patients.insert(patient, at: 0)
        }
        lastModified = Date()
        savePatients()
    }

    func softDeletePatient(_ id: UUID) {
        guard let idx = patients.firstIndex(where: { $0.id == id }) else { return }
        patients[idx].isDeleted = true

        if selectedPatientID == id {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }

        lastModified = Date()
        savePatients()
    }

    func replaceAllPatients(with newPatients: [Patient]) {
        patients = newPatients
        selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        lastModified = Date()
        savePatients()
    }

    // MARK: - Public API (Notes)

    @discardableResult
    func addNote(_ note: RecordNote) -> RecordNote {
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        lastModified = Date()
        saveNotes()
        return note
    }

    func saveNote(_ note: RecordNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
        lastModified = Date()
        saveNotes()
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id { selectedNoteID = notes.first?.id }
        lastModified = Date()
        saveNotes()
    }

    // MARK: - Public API (Attachments)

    func setAttachments(_ newAttachments: [Attachment]) {
        attachments = newAttachments
        lastModified = Date()
        saveAttachments()
    }

    // MARK: - Persistence

    func forcePersistAll() {
        savePatients()
        saveNotes()
        saveAttachments()
    }

    private func loadAll() {
        patients = load([Patient].self, from: patientsURL) ?? []
        notes = load([RecordNote].self, from: notesURL) ?? []
        attachments = load([Attachment].self, from: attachmentsURL) ?? []
        if let v: [SmartVitalsEntry] = load([SmartVitalsEntry].self, from: vitalsURL) {
            vitals = v
        }
    }

    public func savePatients() {
        do {
            let data = try JSONEncoder().encode(patients)
            try data.write(to: patientsURL, options: [.atomic])

            print("✅ savePatients wrote:", patients.count, "patients")
            print("📁 patients.json path:", patientsURL.path)

        } catch {
            print("❌ Save patients failed:", error)
        }
    }

    public func saveNotes() {
        save(notes, to: notesURL)
        maybeAutoBackup()
    }
    
    private func saveVitals() {
        do {
            let data = try JSONEncoder().encode(vitals)
            try data.write(to: vitalsURL, options: [.atomic])
        } catch {
            print("❌ Save vitals failed:", error)
        }
    }

    public func saveAttachments() {
        save(attachments, to: attachmentsURL)
        maybeAutoBackup()
    }

    // MARK: - Auto Backup Hook

    private func maybeAutoBackup() {
        guard let backupCenter else { return }

        let pw = UserDefaults.standard.string(forKey: "EMR_AUTOBACKUP_PASSWORD") ?? ""
        guard !pw.isEmpty else { return }

        backupCenter.autoBackupIfNeeded(store: self, password: pw)
    }

    // MARK: - File URLs

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var patientsURL: URL { documentsURL.appendingPathComponent("patients.json") }
    private var notesURL: URL { documentsURL.appendingPathComponent("notes.json") }
    private var attachmentsURL: URL { documentsURL.appendingPathComponent("attachments.json") }
    
    
    private var vitalsURL: URL { documentsURL.appendingPathComponent("vitals.json") }
    // MARK: - JSON helpers

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("Load failed \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save failed \(url.lastPathComponent): \(error)")
        }
    }

    public func vitalsForPatient(_ patientID: UUID) -> [SmartVitalsEntry] {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    @MainActor
    public func addOrUpdateVitals(
        _ entry: SmartVitalsEntry,
        withinSeconds: TimeInterval = 180
    ) {
        // Find the most recent vitals for THIS patient
        if let idx = vitals
            .enumerated()
            .filter({ $0.element.patientID == entry.patientID })
            .max(by: { $0.element.recordedAt < $1.element.recordedAt })?
            .offset
        {
            let last = vitals[idx]
            let dt = abs(last.recordedAt.timeIntervalSince(entry.recordedAt))

            // If entered within X seconds, treat as same visit and overwrite
            if dt <= withinSeconds {
                var updated = entry
                updated.id = last.id               // keep same ID so list doesn't grow
                vitals[idx] = updated
                lastModified = Date()
                saveVitals()
                return
            }
        }

        // Otherwise it's a new visit → append as new record
        vitals.insert(entry, at: 0)
        lastModified = Date()
        saveVitals()
    }

    public func deleteVitals(_ id: UUID) {
        vitals.removeAll(where: { $0.id == id })
        lastModified = Date()
        saveVitals()
    }
    public func upsertVitals(_ entry: SmartVitalsEntry) {
        if let idx = vitals.firstIndex(where: { $0.id == entry.id }) {
            vitals[idx] = entry               // update existing
        } else {
            vitals.insert(entry, at: 0)       // new
        }
        lastModified = Date()
        saveVitals()
    }
}
