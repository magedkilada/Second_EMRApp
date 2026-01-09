import Foundation
import SwiftUI
import Combine  // ← ADD THIS LINE!

// MARK: - Note Type (keep for backward compatibility with old code)

public enum RecordNoteType: String, Codable, CaseIterable, Identifiable {
    case soap = "SOAP / Progress Note"
    case hp = "H&P"
    case operative = "Operative Note"
    case discharge = "Discharge Summary"
    case eeg = "EEG Report"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .soap: return "SOAP"
        case .hp: return "H&P"
        case .operative: return "Op"
        case .discharge: return "Disch"
        case .eeg: return "EEG"
        }
    }
}

// MARK: - Store

@MainActor
public final class EMRStore: ObservableObject {

    // MARK: - Published Properties
    
    // Patients
    @Published public var patients: [Patient] = []
    @Published public var selectedPatientID: UUID? = nil
    
    // Notes
    @Published public var notes: [RecordNote] = []
    @Published public var selectedNoteID: UUID? = nil
    
    // Attachments
    @Published public var attachments: [Attachment] = []
    
    // Header info (for printing/display)
    @Published public var clinicName: String = "Neurosurgery Clinic"
    @Published public var treatingPhysicianName: String = "Attending Physician"
    
    // Track last modification for UI updates
    @Published public var lastModified: Date = Date()

    // MARK: - Init

    public init() {
        loadPatients()
        loadNotes()
        loadAttachments()
    }

    // MARK: - Patients CRUD

    public func savePatients() {
        do {
            let data = try JSONEncoder().encode(patients)
            UserDefaults.standard.set(data, forKey: "patients_v2")
        } catch {
            print("❌ Failed to save patients:", error)
        }
    }

    private func loadPatients() {
        guard let data = UserDefaults.standard.data(forKey: "patients_v2"),
              let decoded = try? JSONDecoder().decode([Patient].self, from: data) else {
            patients = []
            return
        }
        patients = decoded
    }

    // MARK: - Notes CRUD

    public func notes(for patientID: UUID) -> [RecordNote] {
        notes
            .filter { $0.patientID == patientID && !isPatientDeleted(patientID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func note(by id: UUID) -> RecordNote? {
        notes.first(where: { $0.id == id })
    }

    public func addNote(for patientID: UUID, type: RecordNoteType) -> UUID {
        // Convert RecordNoteType to RecordType
        let recordType: RecordType
        switch type {
        case .soap: recordType = .soap
        case .hp: recordType = .hp
        case .operative: recordType = .operative
        case .discharge: recordType = .discharge
        case .eeg: recordType = .eeg
        }
        
        let new = RecordNote(patientID: patientID, type: recordType)
        notes.insert(new, at: 0)
        selectedNoteID = new.id
        saveNotes()
        return new.id
    }

    public func updateNote(_ note: RecordNote) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
        notes[idx].updatedAt = Date()
        saveNotes()
    }

    public func deleteNote(id: UUID) {
        notes.removeAll(where: { $0.id == id })
        if selectedNoteID == id {
            selectedNoteID = nil
        }
        saveNotes()
    }

    public func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            UserDefaults.standard.set(data, forKey: "notes_v2")
            lastModified = Date()
        } catch {
            print("❌ Failed to save notes:", error)
        }
    }

    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: "notes_v2"),
              let decoded = try? JSONDecoder().decode([RecordNote].self, from: data) else {
            notes = []
            return
        }
        notes = decoded
    }
    
    // NEW: create note directly from RecordType (used by template picker)
    public func addNote(for patientID: UUID, recordType: RecordType) -> UUID {
        let new = RecordNote(patientID: patientID, type: recordType)
        notes.insert(new, at: 0)
        selectedNoteID = new.id
        saveNotes()
        return new.id
    }

    // NEW: replace an existing note body with a template (only if not finalized)
    public func replaceNoteBody(noteID: UUID, with recordType: RecordType) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        guard notes[idx].isFinalized == false else { return }
        notes[idx].type = recordType
        notes[idx].title = (recordType == .blank ? "Clinical Note" : "")
        notes[idx].body = recordType.defaultBody
        notes[idx].updatedAt = Date()
        saveNotes()
    }
    

    // MARK: - Attachments CRUD

    public func attachments(for patientID: UUID) -> [Attachment] {
        attachments
            .filter { $0.patientID == patientID && !isPatientDeleted(patientID) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    public func saveAttachments() {
        do {
            let data = try JSONEncoder().encode(attachments)
            UserDefaults.standard.set(data, forKey: "attachments_v2")
            lastModified = Date()
        } catch {
            print("❌ Failed to save attachments:", error)
        }
    }

    private func loadAttachments() {
        guard let data = UserDefaults.standard.data(forKey: "attachments_v2"),
              let decoded = try? JSONDecoder().decode([Attachment].self, from: data) else {
            attachments = []
            return
        }
        attachments = decoded
    }

    // MARK: - Templates (single source of truth)

    public func templateText(for type: RecordNoteType) -> String {
        let recordType: RecordType
        switch type {
        case .soap: recordType = .soap
        case .hp: recordType = .hp
        case .operative: recordType = .operative
        case .discharge: recordType = .discharge
        case .eeg: recordType = .eeg
        }
        return recordType.defaultBody
    }

    // MARK: - Helpers

    private func isPatientDeleted(_ patientID: UUID) -> Bool {
        patients.first(where: { $0.id == patientID })?.isDeleted ?? false
    }
    // MARK: - Force Persist All (for backup)

    public func forcePersistAll() {
        savePatients()
        saveNotes()
        saveAttachments()
    }

}

