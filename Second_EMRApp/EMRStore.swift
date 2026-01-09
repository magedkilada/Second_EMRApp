import Foundation
import SwiftUI

// MARK: - Note Type

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

// MARK: - Record Note

public struct RecordNote: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID

    public var type: RecordNoteType
    public var body: String

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var isFinalized: Bool = false

    public init(patientID: UUID, type: RecordNoteType, body: String) {
        self.patientID = patientID
        self.type = type
        self.body = body
    }
}

// MARK: - Store

@MainActor
public final class EMRStore: ObservableObject {

    // Notes
    @Published public var notes: [RecordNote] = []
    @Published public var selectedNoteID: UUID? = nil

    // Optional header strings (safe, avoids depending on PhysiciansStore APIs)
    @Published public var clinicName: String = "Clinic"
    @Published public var treatingPhysicianName: String = "Treating Physician"

    // MARK: - Init

    public init() { }

    // MARK: - Notes CRUD

    public func notes(for patientID: UUID) -> [RecordNote] {
        notes
            .filter { $0.patientID == patientID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func note(by id: UUID) -> RecordNote? {
        notes.first(where: { $0.id == id })
    }

    public func addNote(for patientID: UUID, type: RecordNoteType) -> UUID {
        let new = RecordNote(patientID: patientID, type: type, body: templateText(for: type))
        notes.insert(new, at: 0)
        selectedNoteID = new.id
        return new.id
    }

    public func updateNote(_ note: RecordNote) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx] = note
    }

    public func deleteNote(id: UUID) {
        notes.removeAll(where: { $0.id == id })
        if selectedNoteID == id {
            selectedNoteID = nil
        }
    }

    // MARK: - Templates (single source of truth)

    public func templateText(for type: RecordNoteType) -> String {
        switch type {

        case .soap:
            return """
            SUBJECTIVE:
            OBJECTIVE:
            PHYSICAL EXAMINATION:

            VITALS:
            BP: ____ / ____ mmHg
            HR: ____ bpm
            Temp: ____ °C
            O₂ Sat: ____ %

            GENERAL:
            NEUROLOGIC:
            OTHER SYSTEMS:
            Exam:
            Labs / Imaging:

            ASSESSMENT:
            1)
            2)

            PLAN:
            -
            """

        case .hp:
            return """
            CHIEF COMPLAINT:
            HISTORY OF PRESENT ILLNESS:

            PAST MEDICAL HISTORY:
            PAST SURGICAL HISTORY:
            MEDICATIONS:
            ALLERGIES:
            SOCIAL HISTORY:
            FAMILY HISTORY:

            REVIEW OF SYSTEMS:

            PHYSICAL EXAMINATION:
            VITALS:
            GENERAL:
            NEUROLOGIC:
            OTHER SYSTEMS:

            LABS / IMAGING:

            ASSESSMENT:
            -

            PLAN:
            -
            """

        case .operative:
            return """
            PREOPERATIVE DIAGNOSIS:
            POSTOPERATIVE DIAGNOSIS:
            PROCEDURE:
            SURGEON:
            ASSISTANT:
            ANESTHESIA:
            ESTIMATED BLOOD LOSS:
            SPECIMENS:
            DRAINS:
            COMPLICATIONS:

            INDICATIONS:

            DESCRIPTION OF PROCEDURE:

            DISPOSITION:
            """

        case .discharge:
            return """
            ADMISSION DATE:
            DISCHARGE DATE:
            ADMITTING DIAGNOSIS:
            DISCHARGE DIAGNOSIS:

            HOSPITAL COURSE:

            DISCHARGE MEDICATIONS:

            FOLLOW UP:

            DISCHARGE INSTRUCTIONS:
            """

        case .eeg:
            return """
            DATE:
            INDICATION:
            MEDICATIONS:

            TECHNIQUE:
            BACKGROUND:
            ACTIVATION PROCEDURES:
            ABNORMALITIES:

            IMPRESSION:
            """
        }
    }
}
