import Foundation
import CryptoKit
import Security

// MARK: - Encrypted Backup Envelope (JSON on disk)

struct EncryptedBackupEnvelope: Codable {
    var version: Int = 1
    var alg: String = "AES.GCM"
    var createdAt: Date = Date()

    /// AES.GCM.SealedBox.combined base64 (nonce+ciphertext+tag)
    var combined_b64: String
}

// MARK: - Crypto + Keychain

enum BackupCrypto {

    // Change these only if you intentionally want a different “namespace”
    private static let keychainService = "com.magedkilada.Second_EMRApp.backup"
    private static let keychainAccount = "backup-aes256-key-v1"

    /// Returns a cross-device key (iCloud Keychain) if available.
    static func getOrCreateKey() throws -> SymmetricKey {
        if let data = try Keychain.read(service: keychainService, account: keychainAccount, synchronizableAny: true) {
            return SymmetricKey(data: data)
        }

        // Create new key
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }

        // Save as iCloud-synced Keychain item
        try Keychain.save(service: keychainService, account: keychainAccount, data: data, synchronizable: true)

        return key
    }

    static func encryptJSON(_ plaintextJSON: Data) throws -> Data {
        let key = try getOrCreateKey()
        let sealed = try AES.GCM.seal(plaintextJSON, using: key)

        guard let combined = sealed.combined else {
            throw NSError(domain: "BackupCrypto", code: -10, userInfo: [NSLocalizedDescriptionKey: "Failed to build combined sealed box."])
        }

        let env = EncryptedBackupEnvelope(combined_b64: combined.base64EncodedString())
        let out = try JSONEncoder().encode(env)
        return out
    }

    static func decryptJSON(_ encryptedEnvelopeData: Data) throws -> Data {
        let key = try getOrCreateKey()
        let env = try JSONDecoder().decode(EncryptedBackupEnvelope.self, from: encryptedEnvelopeData)

        guard let combined = Data(base64Encoded: env.combined_b64) else {
            throw NSError(domain: "BackupCrypto", code: -11, userInfo: [NSLocalizedDescriptionKey: "Backup file is corrupted (base64 decode failed)."])
        }

        let sealed = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealed, using: key)
        return plaintext
    }
}

// MARK: - Minimal Keychain helper

private enum Keychain {

    static func save(service: String, account: String, data: Data, synchronizable: Bool) throws {
        // Delete existing (if any) then add
        _ = try? delete(service: service, account: account, synchronizableAny: true)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        // iCloud Keychain sync
        query[kSecAttrSynchronizable as String] = synchronizable ? kCFBooleanTrue : kCFBooleanFalse

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (\(status))."])
        }
    }

    static func read(service: String, account: String, synchronizableAny: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Allow matching either synced or local copies
        if synchronizableAny {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain read failed (\(status))."])
        }

        return out as? Data
    }

    static func delete(service: String, account: String, synchronizableAny: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizableAny {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain delete failed (\(status))."])
        }
    }
}
