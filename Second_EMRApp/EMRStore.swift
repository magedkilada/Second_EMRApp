//
//  EMRStore.swift
//  Second_EMRApp
//

import Foundation
import Combine
import UniformTypeIdentifiers

@MainActor
public final class EMRStore: ObservableObject {

    // MARK: - Published State

    @Published public var patients: [Patient] = []
    @Published public var notes: [RecordNote] = []
    @Published public var attachments: [Attachment] = []

    @Published public var selectedPatientID: UUID? = nil
    @Published public var selectedNoteID: UUID? = nil
    @Published public var lastErrorMessage: String? = nil

    // MARK: - Init

    public init() {
        loadPatients()
        loadNotes()
        loadAttachments()

        if selectedPatientID == nil {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - Paths

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var patientsFileURL: URL { documentsURL.appendingPathComponent("patients.json") }
    private var notesFileURL: URL { documentsURL.appendingPathComponent("notes.json") }
    private var attachmentsFileURL: URL { documentsURL.appendingPathComponent("attachments.json") }

    private func patientAttachmentsDir(_ patientID: UUID) -> URL {
        documentsURL
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(patientID.uuidString, isDirectory: true)
    }

    private func ensureAttachmentsDirExists(_ patientID: UUID) throws -> URL {
        let base = documentsURL.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        let dir = patientAttachmentsDir(patientID)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    

    // MARK: - Patients API

    public func visiblePatients() -> [Patient] {
        patients.filter { !$0.isDeleted }
    }

    public func addNewPatient() -> Patient {
        // Minimal safe defaults — your Patient model may have more fields, but this works
        let p = Patient()
        patients.insert(p, at: 0)
        selectedPatientID = p.id
        savePatients()
        return p
    }

    public func savePatient(_ patient: Patient) {
        if let idx = patients.firstIndex(where: { $0.id == patient.id }) {
            patients[idx] = patient
        } else {
            patients.insert(patient, at: 0)
        }
        savePatients()
    }

    public func softDeletePatient(_ patientID: UUID) {
        guard let idx = patients.firstIndex(where: { $0.id == patientID }) else { return }
        patients[idx].isDeleted = true
        savePatients()

        if selectedPatientID == patientID {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    public func hardDeletePatient(_ patientID: UUID) {
        patients.removeAll { $0.id == patientID }
        savePatients()

        // Also remove notes + attachments metadata
        notes.removeAll { $0.patientID == patientID }
        saveNotes()

        attachments.removeAll { $0.patientID == patientID }
        saveAttachments()

        // Also delete attachments folder on disk (best-effort)
        let dir = patientAttachmentsDir(patientID)
        try? FileManager.default.removeItem(at: dir)

        if selectedPatientID == patientID {
            selectedPatientID = patients.first(where: { !$0.isDeleted })?.id
        }
    }

    // MARK: - Notes API  ✅ (THIS FIXES YOUR 3 ERRORS)

    public func notes(for patientID: UUID) -> [RecordNote] {
        notes
            .filter { $0.patientID == patientID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func saveNote(_ note: RecordNote) {
        var updated = note
        updated.updatedAt = Date()

        if let idx = notes.firstIndex(where: { $0.id == updated.id }) {
            notes[idx] = updated
        } else {
            notes.insert(updated, at: 0)
        }
        saveNotes()
    }

    public func deleteNote(_ note: RecordNote) {
        notes.removeAll { $0.id == note.id }
        saveNotes()
    }

    // MARK: - Attachments API

    public func attachments(for patientID: UUID, category: Attachment.Category) -> [Attachment] {
        attachments
            .filter { $0.patientID == patientID && $0.category == category }
            .sorted { $0.importedAt > $1.importedAt }
    }

    public func attachmentFileURL(_ att: Attachment) -> URL {
        patientAttachmentsDir(att.patientID).appendingPathComponent(att.storedFileName)
    }

    /// Copies file into Documents/Attachments/<patientUUID>/ and saves metadata to attachments.json
    @discardableResult
    public func importFile(patientID: UUID,
                           category: Attachment.Category,
                           sourceURL: URL) -> Attachment? {
        do {
            let dir = try ensureAttachmentsDirExists(patientID)

            // IMPORTANT for iOS fileImporter URLs
            let needsSecurity = sourceURL.startAccessingSecurityScopedResource()
            defer { if needsSecurity { sourceURL.stopAccessingSecurityScopedResource() } }

            let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
            let storedName = "\(UUID().uuidString).\(ext)"
            let dest = dir.appendingPathComponent(storedName)

            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)

            let att = Attachment(
                patientID: patientID,
                category: category,
                originalFileName: sourceURL.lastPathComponent,
                storedFileName: storedName
            )

            attachments.insert(att, at: 0)
            saveAttachments()
            return att
        } catch {
            lastErrorMessage = "Import failed: \(error.localizedDescription)"
            return nil
        }
    }

    public func deleteAttachment(_ att: Attachment) {
        do {
            let url = attachmentFileURL(att)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            lastErrorMessage = "Delete file failed: \(error.localizedDescription)"
        }

        attachments.removeAll { $0.id == att.id }
        saveAttachments()
    }

    // MARK: - Load / Save

    private func loadPatients() {
        guard let data = try? Data(contentsOf: patientsFileURL) else { return }
        patients = (try? JSONDecoder().decode([Patient].self, from: data)) ?? []
    }

    private func savePatients() {
        do {
            let data = try JSONEncoder().encode(patients)
            try data.write(to: patientsFileURL, options: [.atomic])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func loadNotes() {
        guard let data = try? Data(contentsOf: notesFileURL) else { return }
        notes = (try? JSONDecoder().decode([RecordNote].self, from: data)) ?? []
    }

    private func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: notesFileURL, options: [.atomic])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func loadAttachments() {
        guard let data = try? Data(contentsOf: attachmentsFileURL) else { return }
        attachments = (try? JSONDecoder().decode([Attachment].self, from: data)) ?? []
    }

    private func saveAttachments() {
        do {
            let data = try JSONEncoder().encode(attachments)
            try data.write(to: attachmentsFileURL, options: [.atomic])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
