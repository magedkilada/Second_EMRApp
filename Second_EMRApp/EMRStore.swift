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
    }

    // MARK: - Public API (Patients)

    @discardableResult
    func addNewPatient() -> Patient {
        let p = Patient()
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
                return
            }
        }

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
            vitals[idx] = entry
        } else {
            vitals.insert(entry, at: 0)
        }
        lastModified = Date()
        saveVitals()
    }
}


