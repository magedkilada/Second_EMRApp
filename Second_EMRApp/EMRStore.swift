//
//  EMRStore.swift
//  Second_EMRApp
//

import Foundation
import Combine

@MainActor
public final class EMRStore: ObservableObject {

    // MARK: - Published

    @Published public var patients: [Patient] = []
    @Published public var notes: [RecordNote] = []
    @Published public var attachments: [Attachment] = []
    @Published public var vitals: [VitalsEntry] = []

    @Published public var selectedPatientID: UUID? = nil
    @Published public var selectedNoteID: UUID? = nil
    @Published public var selectedAttachmentID: UUID? = nil
    @Published public var selectedVitalID: UUID? = nil

    @Published public var searchText: String = ""
    @Published public var lastErrorMessage: String? = nil

    // Header info used by NoteEditorView / printing
    @Published public var treatingPhysicianName: String = "Treating Physician"
    @Published public var clinicName: String = "Clinic"
    @Published public var draftNote: RecordNote? = nil

    // MARK: - Init

    public init() {
        loadAll()

        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - Templates

    public func templateText(for type: RecordNoteType) -> String {
        type.defaultBody
    }

    // MARK: - Notes API

    public func note(by id: UUID) -> RecordNote? {
        notes.first(where: { $0.id == id && !$0.isDeleted })
    }
    
    public func makeDraftNote(patientID: UUID, type: RecordNoteType) -> RecordNote {
        // Not inserted into notes[] until committed
        RecordNote(patientID: patientID, type: type, body: type.defaultBody)
    }

    public func commitDraftNote(_ draft: RecordNote) {
        notes.insert(draft, at: 0)
        saveNotes()
    }

    public func updateNote(_ note: RecordNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
        saveNotes()
    }

    /// Finalize = read-only. Finalized notes cannot be deleted.
    public func finalizeNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[idx].isFinalized { return }
        notes[idx].isFinalized = true
        notes[idx].updatedAt = Date()
        saveNotes()
    }

    /// Unfinalize (admin/correction) — not exposed by default UI.
    public func unfinalizeNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if !notes[idx].isFinalized { return }
        notes[idx].isFinalized = false
        notes[idx].updatedAt = Date()
        saveNotes()
    }

    public func addNote(patientID: UUID, type: RecordNoteType) -> RecordNote {
        let n = RecordNote(patientID: patientID, type: type, body: type.defaultBody)
        notes.insert(n, at: 0)
        selectedNoteID = n.id
        saveNotes()
        return n
    }

    @MainActor
    public func deleteNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        if notes[idx].isFinalized {
            lastErrorMessage = "This note is finalized and cannot be deleted."
            return
        }

        // ✅ Soft delete, but IMPORTANT: reassign array so SwiftUI updates lists
        var copy = notes
        copy[idx].isDeleted = true
        copy[idx].updatedAt = Date()
        notes = copy

        saveNotes()

        if selectedNoteID == id { selectedNoteID = nil }
    }

    // MARK: - Vitals API

    public func vitals(for patientID: UUID) -> [VitalsEntry] {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.measuredAt > $1.measuredAt }
    }

    public func addVital(for patientID: UUID) -> UUID {
        let v = VitalsEntry(patientID: patientID)
        vitals.insert(v, at: 0)
        selectedVitalID = v.id
        saveVitals()
        return v.id
    }

    public func updateVital(_ v: VitalsEntry) {
        if let idx = vitals.firstIndex(where: { $0.id == v.id }) {
            vitals[idx] = v
        } else {
            vitals.insert(v, at: 0)
        }
        saveVitals()
    }

    public func deleteVital(id: UUID) {
        if let idx = vitals.firstIndex(where: { $0.id == id }) {
            vitals.remove(at: idx)
            saveVitals()
        }
    }

    public func latestVital(for patientID: UUID) -> VitalsEntry? {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.measuredAt > $1.measuredAt }
            .first
    }

    // MARK: - Persistence (JSON)

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var patientsURL: URL { documentsURL.appendingPathComponent("patients.json") }
    private var notesURL: URL { documentsURL.appendingPathComponent("notes.json") }
    private var attachmentsURL: URL { documentsURL.appendingPathComponent("attachments.json") }
    private var vitalsURL: URL { documentsURL.appendingPathComponent("vitals.json") }

    private func loadAll() {
        loadPatients()
        loadNotes()
        loadAttachments()
        loadVitals()
    }

    public func forcePersistAll() {
        savePatients()
        saveNotes()
        saveAttachments()
        saveVitals()
    }

    // MARK: Patients

    public func loadPatients() {
        patients = load([Patient].self, from: patientsURL) ?? []
    }

    public func savePatients() {
        save(patients, to: patientsURL)
    }

    // MARK: Notes

    public func loadNotes() {
        notes = load([RecordNote].self, from: notesURL) ?? []
    }

    public func saveNotes() {
        save(notes, to: notesURL)
    }

    // MARK: Attachments

    public func loadAttachments() {
        attachments = load([Attachment].self, from: attachmentsURL) ?? []
    }

    public func saveAttachments() {
        save(attachments, to: attachmentsURL)
    }

    // MARK: Vitals

    public func loadVitals() {
        vitals = load([VitalsEntry].self, from: vitalsURL) ?? []
    }

    public func saveVitals() {
        save(vitals, to: vitalsURL)
    }

    // MARK: - Generic helpers

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let data = try enc.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            lastErrorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            lastErrorMessage = "Load failed: \(error.localizedDescription)"
            return nil
        }
    }
    // MARK: - Attachments helpers

    public func attachmentsDirectory(for patientID: UUID) -> URL {
        let base = documentsURL.appendingPathComponent("PatientAttachments", isDirectory: true)
        let dir = base.appendingPathComponent(patientID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func attachmentFileURL(_ attachment: Attachment) -> URL {
        attachmentsDirectory(for: attachment.patientID).appendingPathComponent(attachment.storedFileName)
    }

    public func deleteAttachment(_ id: UUID, removeFile: Bool = true) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }

        // Soft delete
        let a = attachments[idx]
        attachments[idx].isDeleted = true
        saveAttachments()

        if selectedAttachmentID == id { selectedAttachmentID = nil }

        // Optional physical delete
        if removeFile {
            let url = attachmentFileURL(a)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
