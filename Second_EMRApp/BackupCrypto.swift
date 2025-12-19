import Foundation
import CryptoKit

enum BackupCrypto {

    // Simple container stored in the exported file
    struct EncryptedBlob: Codable {
        var v: Int = 1
        var createdAt: Date
        var saltB64: String
        var combinedB64: String
    }

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = try deriveKey(password: password, salt: salt)

        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "BackupCrypto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Encryption failed (no combined data)."])
        }

        let blob = EncryptedBlob(
            createdAt: Date(),
            saltB64: salt.base64EncodedString(),
            combinedB64: combined.base64EncodedString()
        )

        return try JSONEncoder().encode(blob)
    }

    static func decrypt(_ fileData: Data, password: String) throws -> Data {
        let blob = try JSONDecoder().decode(EncryptedBlob.self, from: fileData)

        guard let salt = Data(base64Encoded: blob.saltB64),
              let combined = Data(base64Encoded: blob.combinedB64) else {
            throw NSError(domain: "BackupCrypto", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid backup file."])
        }

        let key = try deriveKey(password: password, salt: salt)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        // Password → key material
        let inputKey = SymmetricKey(data: Data(password.utf8))

        // HKDF → 256-bit AES key
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("NeuroEMR Backup v1".utf8),
            outputByteCount: 32
        )
        return key
    }
}
