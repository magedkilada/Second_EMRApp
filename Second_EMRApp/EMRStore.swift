//
//  EMRStore.swift
//  Second_EMRApp
//

import Foundation
import Combine
import UniformTypeIdentifiers
import PhotosUI

@MainActor
public final class EMRStore: ObservableObject {
    
    

    // MARK: - Published

    @Published public var patients: [Patient] = []
    @Published public var notes: [RecordNote] = []
    @Published public var attachments: [Attachment] = []
    @Published public var vitals: [VitalsEntry] = []

    @Published public var selectedPatientID: UUID? = nil
    @Published public var selectedNoteID: UUID? = nil
    @Published public var selectedAttachmentID: UUID? = nil
    @Published public var selectedVitalID: UUID? = nil

    @Published public var searchText: String = ""
    @Published public var lastErrorMessage: String? = nil

    // Header info used by NoteEditorView / printing
    @Published public var treatingPhysicianName: String = "Treating Physician"
    @Published public var clinicName: String = "Clinic"
    @Published public var draftNote: RecordNote? = nil
    @Published public var treatingPhysicianPhone: String = ""
    
    
    // MARK: - Init

    public init() {
        loadAll()
        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - Templates

    public func templateText(for type: RecordNoteType) -> String {
        type.defaultBody
    }

    // MARK: - Notes API

    public func note(by id: UUID) -> RecordNote? {
        notes.first(where: { $0.id == id && !$0.isDeleted })
    }

    public func makeDraftNote(patientID: UUID, type: RecordNoteType) -> RecordNote {
        RecordNote(patientID: patientID, type: type, body: type.defaultBody)
    }

    public func commitDraftNote(_ draft: RecordNote) {
        notes.insert(draft, at: 0)
        saveNotes()
    }

    public func updateNote(_ note: RecordNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
        saveNotes()
    }

    public func addNote(patientID: UUID, type: RecordNoteType) -> RecordNote {
        let n = RecordNote(patientID: patientID, type: type, body: type.defaultBody)
        notes.insert(n, at: 0)
        selectedNoteID = n.id
        saveNotes()
        return n
    }

    /// Finalize = read-only. Finalized notes cannot be deleted.
    public func finalizeNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[idx].isFinalized { return }
        notes[idx].isFinalized = true
        notes[idx].updatedAt = Date()
        saveNotes()
    }

    public func unfinalizeNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if !notes[idx].isFinalized { return }
        notes[idx].isFinalized = false
        notes[idx].updatedAt = Date()
        saveNotes()
    }

    public func deleteNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }

        if notes[idx].isFinalized {
            lastErrorMessage = "This note is finalized and cannot be deleted."
            return
        }

        var copy = notes
        copy[idx].isDeleted = true
        copy[idx].updatedAt = Date()
        notes = copy

        saveNotes()
        if selectedNoteID == id { selectedNoteID = nil }
    }

    public func softDeleteNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isDeleted = true
        saveNotes()
        if selectedNoteID == id { selectedNoteID = nil }
    }

    // MARK: - Vitals API

    public func vitals(for patientID: UUID) -> [VitalsEntry] {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.measuredAt > $1.measuredAt }
    }

    public func addVital(for patientID: UUID) -> UUID {
        let v = VitalsEntry(patientID: patientID)
        vitals.insert(v, at: 0)
        selectedVitalID = v.id
        saveVitals()
        return v.id
    }

    public func updateVital(_ v: VitalsEntry) {
        if let idx = vitals.firstIndex(where: { $0.id == v.id }) {
            vitals[idx] = v
        } else {
            vitals.insert(v, at: 0)
        }
        saveVitals()
    }

    public func deleteVital(id: UUID) {
        if let idx = vitals.firstIndex(where: { $0.id == id }) {
            vitals.remove(at: idx)
            saveVitals()
        }
    }

    public func latestVital(for patientID: UUID) -> VitalsEntry? {
        vitals
            .filter { $0.patientID == patientID }
            .sorted { $0.measuredAt > $1.measuredAt }
            .first
    }

    // MARK: - Attachments API

    /// Returns the on-disk file URL for an attachment (in Attachments/<patientID>/storedFileName)
    public func attachmentFileURL(_ attachment: Attachment) -> URL {
        attachmentsDirectory(for: attachment.patientID)
            .appendingPathComponent(attachment.storedFileName)
    }

    /// Soft delete (hide from list). Optionally also removes the physical file.
    public func deleteAttachment(_ id: UUID, removeFile: Bool = false) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }

        let a = attachments[idx]
        attachments[idx].isDeleted = true
        saveAttachments()

        if selectedAttachmentID == id { selectedAttachmentID = nil }

        if removeFile, !a.storedFileName.isEmpty {
            try? FileManager.default.removeItem(at: attachmentFileURL(a))
        }
    }

    /// Hard delete = remove file + remove row
    public func hardDeleteAttachment(_ id: UUID) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
        let a = attachments[idx]

        if !a.storedFileName.isEmpty {
            try? FileManager.default.removeItem(at: attachmentFileURL(a))
        }

        attachments.remove(at: idx)
        saveAttachments()

        if selectedAttachmentID == id { selectedAttachmentID = nil }
    }

    // MARK: - Attachment Import (Files / Photos)

    /// Import from Files (URL). Copies into Attachments/<patientID>/UUID.ext and saves metadata.
    public func importAttachment(from url: URL, patientID: UUID, category: Attachment.Category) {
        do {
            let fm = FileManager.default

            // Ensure per-patient folder exists
            let destDir = attachmentsDirectory(for: patientID)

            // Best-effort original name
            let originalName = (try? url.resourceValues(forKeys: [.nameKey]).name) ?? url.lastPathComponent

            // Choose extension
            let ext = url.pathExtension.isEmpty ? (URL(fileURLWithPath: originalName).pathExtension) : url.pathExtension
            let safeExt = ext.isEmpty ? "dat" : ext.lowercased()

            // Store as UUID filename to avoid collisions
            let storedFileName = "\(UUID().uuidString).\(safeExt)"
            let destURL = destDir.appendingPathComponent(storedFileName)

            // Security-scoped resource handling (Files app)
            let needsSecurity = url.startAccessingSecurityScopedResource()
            defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }

            // Copy
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)

            // ✅ Create model using YOUR initializer
            let a = Attachment(
                patientID: patientID,
                category: category,
                originalFileName: originalName,
                storedFileName: storedFileName
            )

            attachments.insert(a, at: 0)
            saveAttachments()

        } catch {
            lastErrorMessage = "Attachment import failed: \(error.localizedDescription)"
        }
    }

    /// Import photo data (from PhotosPicker).
    public func importPhotoData(_ data: Data, patientID: UUID, category: Attachment.Category, fileExtension: String = "jpg") {
        do {
            let ext = fileExtension.isEmpty ? "jpg" : fileExtension.lowercased()
            let storedFileName = "\(UUID().uuidString).\(ext)"

            let destURL = attachmentsDirectory(for: patientID).appendingPathComponent(storedFileName)
            try data.write(to: destURL, options: [.atomic])

            let a = Attachment(
                patientID: patientID,
                category: category,
                originalFileName: "Photo.\(ext)",
                storedFileName: storedFileName
            )

            attachments.insert(a, at: 0)
            saveAttachments()

        } catch {
            lastErrorMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence (JSON)

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var patientsURL: URL { documentsURL.appendingPathComponent("patients.json") }
    private var notesURL: URL { documentsURL.appendingPathComponent("notes.json") }
    private var attachmentsURL: URL { documentsURL.appendingPathComponent("attachments.json") }
    private var vitalsURL: URL { documentsURL.appendingPathComponent("vitals.json") }

    private func loadAll() {
        loadPatients()
        loadNotes()
        loadAttachments()
        loadVitals()
    }

    public func forcePersistAll() {
        savePatients()
        saveNotes()
        saveAttachments()
        saveVitals()
    }

    // MARK: Patients

    public func loadPatients() {
        patients = load([Patient].self, from: patientsURL) ?? []
    }

    public func savePatients() {
        save(patients, to: patientsURL)
    }

    // MARK: Notes

    public func loadNotes() {
        notes = load([RecordNote].self, from: notesURL) ?? []
    }

    public func saveNotes() {
        save(notes, to: notesURL)
    }

    // MARK: Attachments

    public func loadAttachments() {
        attachments = load([Attachment].self, from: attachmentsURL) ?? []
    }

    public func saveAttachments() {
        save(attachments, to: attachmentsURL)
    }

    // MARK: Vitals

    public func loadVitals() {
        vitals = load([VitalsEntry].self, from: vitalsURL) ?? []
    }

    public func saveVitals() {
        save(vitals, to: vitalsURL)
    }

    // MARK: - Generic helpers

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let data = try enc.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            lastErrorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            lastErrorMessage = "Load failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Attachments helpers (disk paths)

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Root: Documents/Attachments
    public func attachmentsDirectory(for patientID: UUID) -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let base = docs.appendingPathComponent("Attachments", isDirectory: true)
        let patientDir = base.appendingPathComponent(patientID.uuidString, isDirectory: true)

        if !fm.fileExists(atPath: patientDir.path) {
            try? fm.createDirectory(at: patientDir, withIntermediateDirectories: true, attributes: nil)
        }

        return patientDir
    }
    }
