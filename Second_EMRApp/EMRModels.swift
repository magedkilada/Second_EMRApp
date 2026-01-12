//
//  EMRModels.swift
//  Second_EMRApp
//

import Foundation

// MARK: - Basic Enums

public enum Gender: String, Codable, CaseIterable, Identifiable, Hashable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    public var id: String { rawValue }
}

// MARK: - Encounter Type

public enum EncounterType: String, Codable, CaseIterable, Identifiable, Hashable {
    case inpatient = "Inpatient"
    case clinic = "Clinic"
    public var id: String { rawValue }
}

// MARK: - Patient

public struct Patient: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()

    public var nameEnglish: String = ""
    public var nameArabic: String = ""

    public var dob: Date = Date()

    public var mrn: String = ""
    public var nationalID: String = ""
    public var passport: String = ""

    public var phone: String = ""

    // ✅ MUST be public + MUST be in CodingKeys to persist
    public var clinicAppointmentDate: Date? = nil

    public var email: String = ""
    public var gender: Gender = .male

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var isDeleted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, nameEnglish, nameArabic, dob, mrn, nationalID, passport, phone
        case clinicAppointmentDate   // ✅ CRITICAL FIX
        case email, gender
        case createdAt, updatedAt, isDeleted
    }
}
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id
        case nameEnglish
        case nameArabic
        case dob
        case mrn
        case nationalID
        case passport
        case phone
        case clinicAppointmentDate   // ✅ CRITICAL FIX
        case email
        case gender
        case createdAt
        case updatedAt
        case isDeleted
    }

// MARK: - Notes

public enum RecordNoteType: String, Codable, CaseIterable, Identifiable, Hashable {
    case hp = "H&P"
    case soap = "SOAP"
    case operative = "Operative"
    case discharge = "Discharge"
    case eeg = "EEG"
    case prescription = "Prescription"
    case blank = "Blank"

    public var id: String { rawValue }

    /// Hard rule: header is auto-generated from type
    public var headerTitle: String {
        switch self {
        case .hp: return "History & Physical (H&P)"
        case .soap: return "SOAP / Progress Note"
        case .operative: return "Operative Note"
        case .discharge: return "Discharge Summary"
        case .eeg: return "EEG Report"
        case .prescription: return "Prescription"
        case .blank: return "Blank Note"
        }
    }

    /// ✅ Used by AIAssistView and templates list.
    /// IMPORTANT: per your request, vitals should NOT be baked into templates anymore.
    public var defaultBody: String {
        switch self {
        case .hp:
            return """
\(headerTitle)

CHIEF COMPLAINT:

HISTORY OF PRESENT ILLNESS:

PAST MEDICAL HISTORY:

PAST SURGICAL HISTORY:

MEDICATIONS:

ALLERGIES:

FAMILY HISTORY:

SOCIAL HISTORY:

REVIEW OF SYSTEMS:

PHYSICAL EXAMINATION:

IMAGING / LABS:

ASSESSMENT:

PLAN:
"""
        case .soap:
            return """
            SOAP / Progress Note

            SUBJECTIVE:  \n
            OBJECTIVE:  \n
            ASSESSMENT:  \n
            PLAN:  \n
            """
        case .operative:
            return """
\(headerTitle)

PREOPERATIVE DIAGNOSIS:

POSTOPERATIVE DIAGNOSIS:

PROCEDURE:

SURGEON:

ASSISTANT:

ANESTHESIA:

POSITION:

FINDINGS:

ESTIMATED BLOOD LOSS:

DRAINS:

COMPLICATIONS:

INDICATIONS:

DESCRIPTION OF PROCEDURE:
"""
        case .discharge:
            return """
\(headerTitle)

ADMISSION DATE:

DISCHARGE DATE:

ADMITTING DIAGNOSIS:

DISCHARGE DIAGNOSIS:

HOSPITAL COURSE:

PROCEDURES:

DISCHARGE MEDICATIONS:

DISCHARGE INSTRUCTIONS:

FOLLOW UP:
"""
        case .eeg:
            return """
\(headerTitle)

INDICATION:

MEDICATIONS:

TECHNIQUE:

FINDINGS:

IMPRESSION:
"""
        case .prescription:
            return """
\(headerTitle)

DIAGNOSIS:

MEDICATIONS:

INSTRUCTIONS:
"""
        case .blank:
            return """
        \(headerTitle)

        TITLE:  

        """
        }
    }
}

/// Backwards compatibility for parts of your UI that still refer to RecordType
public typealias RecordType = RecordNoteType

public struct RecordNote: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID

    public var type: RecordNoteType = .soap

    /// Some screens set `note.title = ...` (AIWorkspacePane). Keep it optional.
    public var title: String? = nil

    public var body: String
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var isFinalized: Bool = false
    public var isDeleted: Bool = false

    public init(patientID: UUID, type: RecordNoteType, body: String? = nil) {
        self.patientID = patientID
        self.type = type
        self.body = body ?? type.defaultBody
    }

    public var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return type.rawValue
    }
}

// MARK: - Attachments

public struct Attachment: Identifiable, Codable, Hashable {
    public enum Category: String, Codable, CaseIterable, Identifiable, Hashable {
        case radiology = "Radiology"
        case laboratory = "Laboratory"
        case specialTest = "Special Test"
        case medicalReport = "Medical Report"
        public var id: String { rawValue }
    }

    public var id: UUID = UUID()
    public var patientID: UUID

    public var category: Category = .radiology
    public var originalFileName: String = ""
    public var storedFileName: String = ""
    public var importedAt: Date = Date()
    public var isDeleted: Bool = false

    public init(patientID: UUID, category: Category = .radiology, originalFileName: String = "", storedFileName: String = "") {
        self.patientID = patientID
        self.category = category
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
    }
}

