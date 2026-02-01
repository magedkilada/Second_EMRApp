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

    public var phone: String = ""
    public var email: String = ""

    public var mrn: String = ""
    public var nationalID: String = ""
    public var passport: String = ""

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var isDeleted: Bool = false

    public init() { }

    public var ageString: String? {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: dob, to: now)
        
        guard let years = components.year, let months = components.month else {
            return nil
        }
        
        if years > 0 {
            if months > 0 {
                return "\(years)y \(months)m"
            } else {
                return "\(years)y"
            }
        } else {
            return "\(months)m"
        }
    }
}

// MARK: - Record Types

public enum RecordType: String, Codable, CaseIterable, Identifiable {
    case hp = "H&P"
    case soap = "SOAP"
    case operative = "Operative"
    case discharge = "Discharge"
    case eeg = "EEG"
    case prescription = "Prescription"
    case blank = "Clinical Note" // Adjusted for consistency

    public var id: String { rawValue }

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

    // ✅ FIXED: NO MANUAL VITALS - Smart Vitals button inserts automatically
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
            LABS / RADIOLOGY:

            ASSESSMENT:
            PLAN:
            """
        case .soap:
            return """
            SUBJECTIVE:
            OBJECTIVE:
              PHYSICAL EXAMINATION:
              LABS / RADIOLOGY:

            ASSESSMENT:

            PLAN:
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
            Rx

            Drug Name:  
            Strength:  
            Route:  
            Frequency:  
            Duration:

            Quantity:  
            Refills:

            Instructions:

            Prescriber Signature: _______________
            Date: _______________
            """
        case .blank:
            return ""
        }
    }
}

// MARK: - RecordNote

public struct RecordNote: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID
    public var type: RecordType = .soap
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var body: String = ""

    // ✅ Finalization support
    public var isFinalized: Bool = false
    public var finalizedAt: Date? = nil
    public var isDeleted: Bool = false

    public init(patientID: UUID, type: RecordType = .soap) {
        self.patientID = patientID
        self.type = type
        self.body = type.defaultBody
    }

    public var displayTitle: String {
        type.headerTitle
    }
}

// MARK: - Attachment

public enum AttachmentType: String, Codable, CaseIterable, Identifiable {
    case radiology = "Radiology"
    case laboratory = "Laboratory"
    case eeg = "EEG"
    case medicalReport = "Medical Report"
    case other = "Other"

    public var id: String { rawValue }
}

public struct Attachment: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID
    public var type: AttachmentType = .other
    public var filename: String = ""
    /// Relative path from the Documents directory (e.g. "AttachmentFiles/UUID_file.pdf").
    /// Older data may still have an absolute URL stored — resolvedFileURL handles both.
    public var fileURL: URL?
    public var createdAt: Date = Date()
    public var isDeleted: Bool = false

    public init(patientID: UUID, type: AttachmentType = .other) {
        self.patientID = patientID
        self.type = type
    }

    /// Resolves the file URL at runtime so it survives app-container changes and cross-device sync.
    public var resolvedFileURL: URL? {
        let fm = FileManager.default
        let attachDir = iCloudSyncManager.shared.directoryURL(for: "AttachmentFiles")

        // 1. If the stored absolute URL still exists on disk, use it.
        if let url = fileURL, fm.fileExists(atPath: url.path) {
            return url
        }

        // 2. Try the standardized path (resolves symlinks / percent-encoding differences).
        if let url = fileURL {
            let standardized = url.standardizedFileURL
            if fm.fileExists(atPath: standardized.path) {
                return standardized
            }
        }

        // 3. Try reconstructing from the last path component in current AttachmentFiles dir.
        if let url = fileURL {
            let name = url.lastPathComponent
            let candidate = attachDir.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            // Also try percent-decoded version
            if let decoded = name.removingPercentEncoding, decoded != name {
                let candidate2 = attachDir.appendingPathComponent(decoded)
                if fm.fileExists(atPath: candidate2.path) {
                    return candidate2
                }
            }
        }

        // 4. Fallback: search directory for a file matching the filename.
        if !filename.isEmpty {
            if let contents = try? fm.contentsOfDirectory(atPath: attachDir.path) {
                if let match = contents.first(where: { $0.hasSuffix(filename) || $0 == filename }) {
                    return attachDir.appendingPathComponent(match)
                }
            }
        }

        return nil
    }
}

