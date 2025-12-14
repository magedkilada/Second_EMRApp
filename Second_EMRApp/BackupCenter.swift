import Foundation
import Combine
import CryptoKit
import Security

@MainActor
final class BackupCenter: ObservableObject {

    // MARK: - Published UI state
    @Published var isICloudAvailable: Bool = false
    @Published var lastBackupDate: Date? = nil
    @Published var lastErrorMessage: String? = nil

    // MARK: - User prefs
    private let autoBackupKey = "backup.auto.enabled"

    var autoBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoBackupKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoBackupKey) }
    }

    // MARK: - Constants
    private let keychainService = "Second_EMRApp.BackupCenter"
    private let keychainAccount = "backup.symmetricKey.v1"

    private let folderName = "SecondEMRBackups"
    private let backupFileName = "patients.enc"
    private let metaFileName   = "patients.meta"   // stores timestamp string

    init() { }

    // MARK: - Lifecycle
    func configureIfNeeded() {
        isICloudAvailable = (FileManager.default.ubiquityIdentityToken != nil)
        lastBackupDate = readBackupDateFromDisk()
    }

    // MARK: - Public API

    /// Encrypt + write latest snapshot to disk (iCloud if available, else local Documents)
    func backupNow(patients: [Patient]) {
        do {
            let data = try JSONEncoder().encode(patients)
            let encrypted = try encrypt(data)

            let dir = try ensureBackupDirectory()
            let encURL = dir.appendingPathComponent(backupFileName)
            try encrypted.write(to: encURL, options: .atomic)

            let now = Date()
            try writeBackupDate(now, in: dir)

            lastBackupDate = now
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    /// Restore latest snapshot from disk. Returns nil on failure (see lastErrorMessage).
    func restoreLatest() -> [Patient]? {
        do {
            let dir = try ensureBackupDirectory()
            let encURL = dir.appendingPathComponent(backupFileName)

            guard FileManager.default.fileExists(atPath: encURL.path) else {
                lastErrorMessage = "No backup file found."
                return nil
            }

            let encrypted = try Data(contentsOf: encURL)
            let decrypted = try decrypt(encrypted)

            let patients = try JSONDecoder().decode([Patient].self, from: decrypted)

            lastBackupDate = readBackupDateFromDisk()
            lastErrorMessage = nil
            return patients
        } catch {
            lastErrorMessage = "Restore failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Paths

    private func ensureBackupDirectory() throws -> URL {
        let fm = FileManager.default

        // Prefer iCloud container if available
        if let iCloudRoot = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = iCloudRoot
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)

            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        // Fallback: local Documents
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeBackupDate(_ date: Date, in dir: URL) throws {
        let metaURL = dir.appendingPathComponent(metaFileName)
        let metaString = String(Int(date.timeIntervalSince1970))
        guard let data = metaString.data(using: .utf8) else { return }
        try data.write(to: metaURL, options: .atomic)
    }

    private func readBackupDateFromDisk() -> Date? {
        do {
            let dir = try ensureBackupDirectory()
            let metaURL = dir.appendingPathComponent(metaFileName)
            guard FileManager.default.fileExists(atPath: metaURL.path) else { return nil }

            let data = try Data(contentsOf: metaURL)
            let s = String(data: data, encoding: .utf8) ?? ""
            let secs = TimeInterval(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            return secs > 0 ? Date(timeIntervalSince1970: secs) : nil
        } catch {
            return nil
        }
    }

    // MARK: - Crypto

    private func encrypt(_ plaintext: Data) throws -> Data {
        let key = try loadOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "BackupCenter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Encryption failed (no combined box)."])
        }
        return combined
    }

    private func decrypt(_ ciphertext: Data) throws -> Data {
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = keychainRead(service: keychainService, account: keychainAccount) {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        keychainWrite(service: keychainService, account: keychainAccount, data: data)
        return key
    }

    // MARK: - Keychain

    private func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func keychainWrite(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // delete then add
        SecItemDelete(query as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemAdd(add as CFDictionary, nil)
    }
}
