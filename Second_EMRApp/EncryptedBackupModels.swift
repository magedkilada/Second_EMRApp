import Foundation

public struct BackupPayload: Codable {
    public let patients: [Patient]
    public let notes: [RecordNote]
    public let attachments: [Attachment]
    public let createdAt: Date
    public let appVersion: String

    public init(patients: [Patient], notes: [RecordNote], attachments: [Attachment],
                createdAt: Date = Date(),
                appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown") {
        self.patients = patients
        self.notes = notes
        self.attachments = attachments
        self.createdAt = createdAt
        self.appVersion = appVersion
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
