import Foundation

// MARK: - Patient

public enum Gender: String, Codable, CaseIterable, Identifiable {
    case male = "Male"
    case female = "Female"
    case other = "Other"
    public var id: String { rawValue }
}

public struct Patient: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()

    public var nameEnglish: String = ""
    public var nameArabic: String = ""

    public var dob: Date = Date()
    public var gender: Gender = .male

    public var phone: String = ""          // REQUIRED
    public var email: String = ""

    public var mrn: String = ""            // digits only (enforced in UI)
    public var nationalID: String = ""      // digits only (enforced in UI)
    public var passport: String = ""        // alphanumeric caps (enforced in UI)

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var isDeleted: Bool = false

    public init() {}
}

// MARK: - Record Types

public enum RecordType: String, Codable, CaseIterable, Identifiable {
    case hp = "H&P"
    case soap = "SOAP"
    case operative = "Operative"
    case discharge = "Discharge"
    case eeg = "EEG"
    case prescription = "Prescription"
    case blank = "Blank"

    public var id: String { rawValue }

    // HARD RULE: header is always generated from type
    public var headerTitle: String {
        switch self {
        case .hp: return "History & Physical (H&P)"
        case .soap: return "SOAP / Progress Note"
        case .operative: return "Operative Note"
        case .discharge: return "Discharge Summary"
        case .eeg: return "Electroencephalography (EEG) Report"
        case .prescription: return "Prescription"
        case .blank: return "Clinical Note"
        }
    }

    public var defaultBody: String {
        switch self {
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

ASSESSMENT:  
PLAN:  
"""
        case .soap:
            return """
SUBJECTIVE:  
OBJECTIVE:  
Vitals:  
Exam:  
Labs / Imaging:  

ASSESSMENT:  
1)  
2)  

PLAN:  
-  
"""
        case .operative:
            return """
PREOPERATIVE DIAGNOSIS:  
POSTOPERATIVE DIAGNOSIS:  

PROCEDURE:  
SURGEON:  
ASSISTANTS:  
ANESTHESIA:  

INDICATIONS:  

FINDINGS:  

DESCRIPTION OF PROCEDURE:  

ESTIMATED BLOOD LOSS:  
COMPLICATIONS:  
DRAINS:  
SPECIMENS:  

DISPOSITION:  
"""
        case .discharge:
            return """
ADMISSION DATE:  
DISCHARGE DATE:  

ADMISSION DIAGNOSIS:  
DISCHARGE DIAGNOSIS:  

HOSPITAL COURSE:  

PROCEDURES / OPERATIONS:  
CONSULTS:  

DISCHARGE MEDICATIONS:  

DISCHARGE INSTRUCTIONS:  
FOLLOW UP:  
"""
        case .eeg:
            return """
CLINICAL HISTORY:  
REASON:  
HISTORY:  
NOTES:  

TECHNICAL DETAILS:
DURATION:  30 min
MONTAGE:  10-20 system
STATE:  Awake/Asleep
ACTIVATIONS:  Hyperventilation [ ]  Photic stimulation [ ]

EEG FINDINGS:
BACKGROUND:  
FOCAL:  
GENERALIZED:  
SEIZURES:  

IMPRESSION:  

RECOMMENDATIONS:  
"""
        case .prescription:
            return """
EPISODE DIAGNOSIS:  

MEDICATION:  
DOSE:  
ROUTE:  
FREQUENCY:  
DURATION:  

REFILLS:  

INDICATION:  
SPECIAL INSTRUCTIONS:  
"""
        case .blank:
            return """
TITLE:  
BODY:  
"""
        }
    }
}

// MARK: - Record Note

public struct RecordNote: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID

    public var type: RecordType
    public var title: String = ""      // mostly for Blank
    public var body: String

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var isFinalized: Bool = false
    public var finalizedAt: Date? = nil

    // Prescription helpers (optional)
    public var episodeDiagnosis: String = ""     // can be used for batch Rx print/share
    public var medicationKey: String = ""        // for grouping prescriptions

    public init(patientID: UUID, type: RecordType) {
        self.patientID = patientID
        self.type = type
        self.body = type.defaultBody
    }
}

// MARK: - Attachments

public struct Attachment: Identifiable, Codable, Hashable {

    public enum Category: String, Codable, CaseIterable, Identifiable {
        case radiology = "Radiology"
        case laboratory = "Laboratory"
        case specialTest = "Special Test"
        case medicalReport = "Medical Report"
        public var id: String { rawValue }
    }

    public var id: UUID = UUID()
    public var patientID: UUID

    public var category: Category
    public var originalFileName: String
    public var storedFileName: String        // filename saved in app Documents
    public var importedAt: Date = Date()

    public init(patientID: UUID,
                category: Category,
                originalFileName: String,
                storedFileName: String) {
        self.patientID = patientID
        self.category = category
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.importedAt = Date()
    }
}
