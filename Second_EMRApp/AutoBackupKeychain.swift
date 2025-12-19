import Foundation
import Security

enum AutoBackupKeychain {
    // Change this string once and keep it stable.
    // It identifies the saved password.
    private static let service = "com.magedkilada.neuroemr.autobackup"
    private static let account = "autobackup-password"

    /// Save password to Keychain (device-only).
    static func save(_ password: String) throws {
        let data = Data(password.utf8)

        // Delete old value first (simplest & reliable)
        try? delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,

            // Device-only (NO iCloud Keychain sync)
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,

            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "AutoBackupKeychain", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain save failed (status \(status))."
            ])
        }
    }

    /// Load password from Keychain.
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,

            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }

        return str
    }

    /// Delete password from Keychain.
    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: "AutoBackupKeychain", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain delete failed (status \(status))."
            ])
        }
    }
}
