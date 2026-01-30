import Foundation

// MARK: - Medical Record Model
struct MedicalRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var type: MedicalRecordType
    var date: Date
    var content: String
    var isFinalized: Bool
    var finalizedDate: Date?
    var attachments: [RecordAttachment]

    init(id: UUID = UUID(),
         type: MedicalRecordType,
         date: Date = Date(),
         content: String = "",
         isFinalized: Bool = false,
         finalizedDate: Date? = nil,
         attachments: [RecordAttachment] = []) {
        self.id = id
        self.type = type
        self.date = date
        self.content = content
        self.isFinalized = isFinalized
        self.finalizedDate = finalizedDate
        self.attachments = attachments
    }

    static func == (lhs: MedicalRecord, rhs: MedicalRecord) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Record Type Enum
enum MedicalRecordType: String, Codable, CaseIterable {
    case historyAndPhysical = "History & Physical (H&P)"
    case soapNote = "SOAP / Progress Note"
    case operativeNote = "Operative Note"
    case dischargeSummary = "Discharge Summary"
    case eegReport = "EEG Report"
    case prescription = "Prescription"
}

// MARK: - Attachment Model
struct RecordAttachment: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let category: String
    let date: Date
    let fileURL: URL?

    init(id: UUID = UUID(),
         fileName: String,
         category: String,
         date: Date = Date(),
         fileURL: URL? = nil) {
        self.id = id
        self.fileName = fileName
        self.category = category
        self.date = date
        self.fileURL = fileURL
    }

    static func == (lhs: RecordAttachment, rhs: RecordAttachment) -> Bool {
        return lhs.id == rhs.id
    }
}

