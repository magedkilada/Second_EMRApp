import Foundation

public struct BackupPayload: Codable {
    public let patients: [Patient]
    public let notes: [RecordNote]
    public let attachments: [Attachment]
    public let vitals: [SmartVitalsEntry]
    public let createdAt: Date
    public let appVersion: String

    public init(patients: [Patient], notes: [RecordNote], attachments: [Attachment],
                vitals: [SmartVitalsEntry] = [],
                createdAt: Date = Date(),
                appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") {
        self.patients = patients
        self.notes = notes
        self.attachments = attachments
        self.vitals = vitals
        self.createdAt = createdAt
        self.appVersion = appVersion
    }

    // Backward-compatible decoder: older backups may lack "vitals"
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        patients = try c.decode([Patient].self, forKey: .patients)
        notes = try c.decode([RecordNote].self, forKey: .notes)
        attachments = try c.decode([Attachment].self, forKey: .attachments)
        vitals = (try? c.decode([SmartVitalsEntry].self, forKey: .vitals)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        appVersion = try c.decode(String.self, forKey: .appVersion)
    }
}

public struct EncryptedBackup: Codable {
    public let salt: Data
    public let nonce: Data
    public let ciphertextPlusTag: Data

    public init(salt: Data, nonce: Data, ciphertextPlusTag: Data) {
        self.salt = salt
        self.nonce = nonce
        self.ciphertextPlusTag = ciphertextPlusTag
    }
}
