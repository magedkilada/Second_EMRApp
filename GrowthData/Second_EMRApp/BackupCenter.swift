//
//  BackupCenter.swift
//  Second_EMRApp
//

import Foundation
import CryptoKit
import Combine

@MainActor
final class BackupCenter: ObservableObject {

    // MARK: - Published UI State

    @Published var lastBackupDate: Date? = nil
    @Published var lastErrorMessage: String? = nil
    // MARK: - Auto-backup settings (throttle)

    private let minAutoBackupInterval: TimeInterval = 5 * 60 // 5 minutes
    private var lastAutoBackupWrite: Date? = nil

    // MARK: - Public API (Manual export/import)

    /// Creates an encrypted backup file (used by FileExporter).
    /// Requires `BackupPayload` and `BackupFileDocument` to already exist in your project.
    func makeEncryptedBackup(store: EMRStore, password: String) -> BackupFileDocument? {
        do {
            let data = try encryptedBackupData(from: store, password: password)
            lastBackupDate = Date()
            lastErrorMessage = nil
            return BackupFileDocument(data: data)
        } catch {
            lastErrorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Restores from encrypted file data (used by FileImporter).
    /// Fast-fails with “wrong password or corrupted file” instead of CryptoKit noise.
    func restoreEncryptedBackup(into store: EMRStore, fileData: Data, password: String) {
        do {
            // fast-fail verification
            guard looksLikeOurBackupFile(fileData) else {
                throw NSError(domain: "BackupCenter", code: -10,
                              userInfo: [NSLocalizedDescriptionKey: "Not a valid EMR backup file."])
            }

            let payload = try decryptPayload(fileData, password: password)

            // Replace everything
            store.patients = payload.patients
            store.notes = payload.notes
            store.attachments = payload.attachments

            // Reselect something reasonable
            store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
            store.selectedNoteID = nil

            // Persist using your existing store persistence method
            store.forcePersistAll()

            lastBackupDate = payload.createdAt
            lastErrorMessage = nil
        } catch {
            // keep message friendly
            lastErrorMessage = "Import failed: wrong password or corrupted file."
        }
    }

    // MARK: - Auto Backup (local file inside Documents/Backups)

    /// Call this when you want an automatic local backup (e.g., after Save Patient).
    /// It throttles to max once every 5 minutes.
    func autoBackupIfNeeded(store: EMRStore, password: String) {
        let now = Date()
        if let last = lastAutoBackupWrite, now.timeIntervalSince(last) < minAutoBackupInterval {
            return
        }

        do {
            let data = try encryptedBackupData(from: store, password: password)
            try writeAutoBackupFile(data)
            lastAutoBackupWrite = now
            lastBackupDate = now
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Auto-backup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Internals (encode + encrypt)

    private func encryptedBackupData(from store: EMRStore, password: String) throws -> Data {
        let payload = BackupPayload(
            patients: store.patients,
            notes: store.notes,
            attachments: store.attachments
        )

        let json = try JSONEncoder().encode(payload)
        return try encrypt(json: json, password: password)
    }

    // MARK: - File format: MAGIC(4) + VER(1) + SALT(16) + NONCE(12) + TAG(16) + CIPHERTEXT

    private let magic: [UInt8] = [0x45, 0x4D, 0x52, 0x31] // "EMR1"
    private let version: UInt8 = 1
    private let saltLen = 16
    private let nonceLen = 12
    private let tagLen = 16

    private func looksLikeOurBackupFile(_ data: Data) -> Bool {
        guard data.count >= 4 + 1 + saltLen + nonceLen + tagLen else { return false }
        let m = [UInt8](data.prefix(4))
        return m == magic
    }

    private func encrypt(json: Data, password: String) throws -> Data {
        let salt = randomBytes(count: saltLen)
        let key = deriveKey(password: password, salt: salt)

        let nonceBytes = randomBytes(count: nonceLen)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        let sealed = try AES.GCM.seal(json, using: key, nonce: nonce)

        guard let tag = sealed.tag as Data? else {
            throw NSError(domain: "BackupCenter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Encryption failed (no tag)."])
        }

        // CryptoKit stores nonce separately; we store our own nonce bytes
        let ciphertext = sealed.ciphertext

        var out = Data()
        out.append(contentsOf: magic)
        out.append(version)
        out.append(salt)
        out.append(nonceBytes)
        out.append(tag)
        out.append(ciphertext)
        return out
    }

    private func decryptPayload(_ data: Data, password: String) throws -> BackupPayload {
        // Minimum length check
        let minLen = 4 + 1 + saltLen + nonceLen + tagLen + 1
        guard data.count >= minLen else {
            throw NSError(domain: "BackupCenter", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Backup file is too small."])
        }

        var idx = 0

        // MAGIC
        let fileMagic = [UInt8](data[idx..<idx+4]); idx += 4
        guard fileMagic == magic else {
            throw NSError(domain: "BackupCenter", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Not a valid EMR backup file."])
        }

        // VER
        let ver = data[idx]; idx += 1
        guard ver == version else {
            throw NSError(domain: "BackupCenter", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported backup version."])
        }

        // SALT
        let salt = data[idx..<idx+saltLen]; idx += saltLen
        // NONCE
        let nonceBytes = data[idx..<idx+nonceLen]; idx += nonceLen
        // TAG
        let tag = data[idx..<idx+tagLen]; idx += tagLen
        // CIPHERTEXT
        let ciphertext = data[idx...]

        let key = deriveKey(password: password, salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        let sealed = try AES.GCM.SealedBox(nonce: nonce,
                                          ciphertext: ciphertext,
                                          tag: tag)

        let plain = try AES.GCM.open(sealed, using: key)
        return try JSONDecoder().decode(BackupPayload.self, from: plain)
    }

    // MARK: - Key derivation

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        // PBKDF2-like using HKDF is acceptable for your app use-case,
        // but we’ll keep it deterministic+portable:
        let inputKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("NeurosurgeryEMR.Backup".utf8),
            outputByteCount: 32
        )
    }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - Local auto-backup file path

    private func ensureBackupDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Backups", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func autoBackupFileURL() throws -> URL {
        let dir = try ensureBackupDirectory()
        return dir.appendingPathComponent("AutoBackup.emrbackup")
    }

    private func writeAutoBackupFile(_ data: Data) throws {
        let url = try autoBackupFileURL()
        try data.write(to: url, options: [.atomic])
    }
}
