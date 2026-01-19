//
//  RecordsWorkspaceView.swift
//  Second_EMRApp
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import QuickLook
import UIKit

struct RecordsWorkspaceView: View {

    // MARK: - Input
    let patient: Patient

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - iPhone Navigation
    enum PhoneRoute: Hashable {
        case note(UUID)
        case attachment(UUID)
    }
    @State private var phonePath: [PhoneRoute] = []   // MUST exist once

    // MARK: - Selection
    @State private var selectedAttachmentID: UUID? = nil

    private var selectedNoteIsFinalized: Bool {
        guard let id = store.selectedNoteID,
              let n = noteByID(id) else { return false }
        return n.isFinalized
    }

    // MARK: - Import UI
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []

    // MARK: - Errors
    @State private var errorMessage: String?

    // MARK: - QuickLook
    // MARK: - QuickLook
    @State private var previewItem: PreviewItem? = nil

    private struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }


    // MARK: - Body
    var body: some View {
        Group {
            if isPhone {
                phoneNavigationLayout
            } else {
                ipadSplitLayout
            }
        }
        .toolbar { topRightToolbar }

        // File import
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .content, .item],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                importPickedFile(url)
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }

        // Photo import
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickedPhotos,
            maxSelectionCount: 1,
            matching: .images
        )
        .onChange(of: pickedPhotos) { _, newItems in
            guard let item = newItems.first else { return }
            Task { await importPickedPhoto(item) }
        }

        // Error alert
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }

        // Preview sheet
        // Preview sheet (opens ONLY when we have a URL)
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
    }

    // MARK: - iPhone layout (reliable push)
    private var phoneNavigationLayout: some View {
        NavigationStack(path: $phonePath) {
            recordsList
                .navigationTitle(patientName)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case .note(let id):
                        noteEditorDestination(noteID: id)
                            .environmentObject(physicians) // ✅ critical to prevent crash/freeze
                    case .attachment(let id):
                        attachmentDestination(attachmentID: id)
                    }
                }
        }
    }

    // MARK: - iPad layout
    private var ipadSplitLayout: some View {
        NavigationSplitView {
            recordsList
                .navigationTitle("Medical Records")
        } detail: {
            recordsDetail
                .navigationTitle(patientName)
        }
    }

    private var recordsDetail: some View {
        Group {
            if let noteID = store.selectedNoteID {
                noteEditorDestination(noteID: noteID)
                    .environmentObject(physicians)
            } else if let attID = selectedAttachmentID {
                attachmentDestination(attachmentID: attID)
            } else {
                ContentUnavailableView("Select a note", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shared list
    private var recordsList: some View {
        List {
            Section("Notes") {
                if notesForPatient.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notesForPatient) { note in
                        Button {
                            // selection first
                            store.selectedNoteID = note.id
                            selectedAttachmentID = nil

                            // then push on phone
                            if isPhone {
                                phonePath.append(.note(note.id))
                            }
                        } label: {
                            noteRow(note)
                                .contentShape(Rectangle()) // ✅ ensures full-row tap
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            store.selectedNoteID == note.id
                            ? Color.yellow.opacity(0.25)
                            : Color.clear
                        )
                    }
                }
            }

            Section("Attachments") {
                if attachmentsForPatient.isEmpty {
                    Text("No attachments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentsForPatient) { att in
                        Button {
                            selectedAttachmentID = att.id
                            store.selectedNoteID = nil

                            if isPhone {
                                phonePath.append(.attachment(att.id))
                            }
                        } label: {
                            attachmentRow(att)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedAttachmentID == att.id
                            ? Color.yellow.opacity(0.18)
                            : Color.clear
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Rows
    private func noteRow(_ note: RecordNote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if note.isFinalized {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func attachmentRow(_ att: Attachment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(att.originalFileName)
                    .font(.headline)
                    .lineLimit(1)

                Text(att.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "paperclip")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Destinations
    private func noteEditorDestination(noteID: UUID) -> some View {
        Group {
            if let binding = bindingForNote(id: noteID) {
                NoteEditorView(note: binding, patient: patient) { saved in
                    // mutate via binding (this ensures list refresh)
                    var n = saved
                    n.updatedAt = Date()
                    binding.wrappedValue = n
                    store.lastModified = Date()
                }
                .onAppear {
                    store.selectedNoteID = noteID
                    selectedAttachmentID = nil
                }
            } else {
                Text("Note not found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private func attachmentDestination(attachmentID: UUID) -> some View {
        Group {
            if let att = attachmentByID(attachmentID),
               let url = attachmentFileURL(att) {

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        previewItem = PreviewItem(url: url)
                    } label: {
                        Label("Open Preview", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(att.originalFileName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding()
                .onAppear {
                    selectedAttachmentID = attachmentID
                    store.selectedNoteID = nil
                }

            } else {
                Text("Attachment not found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Attachment")
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {

            if store.selectedNoteID != nil {
                Button {
                    finalizeSelectedNote()
                } label: {
                    Label(
                        selectedNoteIsFinalized ? "Finalized" : "Finalize",
                        systemImage: selectedNoteIsFinalized ? "lock.fill" : "checkmark.seal"
                    )
                }
                .disabled(selectedNoteIsFinalized)
            }

            // New note
            Menu {
                Button("H&P")          { addNote(type: RecordType.hp) }
                Button("SOAP")         { addNote(type: RecordType.soap) }
                Button("Operative")    { addNote(type: RecordType.operative) }
                Button("Discharge")    { addNote(type: RecordType.discharge) }
                Button("EEG")          { addNote(type: RecordType.eeg) }
                Button("Prescription") { addNote(type: RecordType.prescription) }
                Button("Clinical Note"){ addNote(type: RecordType.blank) }
            } label: {
                Image(systemName: "square.and.pencil")
            }

            // Import
            Menu {
                Menu("Import File…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showFileImporter = true
                        }
                    }
                }
                Menu("Import Photo…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showPhotoPicker = true
                        }
                    }
                }
            } label: {
                Image(systemName: "paperclip")
            }

            // Delete
            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)
        }
    }

    // MARK: - Data helpers
    private var patientName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ar.isEmpty { return ar }
        return "Patient"
    }

    private var notesForPatient: [RecordNote] {
        store.notes
            .filter { $0.patientID == patient.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var attachmentsForPatient: [Attachment] {
        store.attachments
            .filter { $0.patientID == patient.id }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private func noteByID(_ id: UUID) -> RecordNote? {
        store.notes.first(where: { $0.id == id })
    }

    private func attachmentByID(_ id: UUID) -> Attachment? {
        store.attachments.first(where: { $0.id == id })
    }

    private func bindingForNote(id: UUID) -> Binding<RecordNote>? {
        guard let idx = store.notes.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.notes[idx]
    }

    // MARK: - Actions
    private func addNote(type: RecordType) {
        var n = RecordNote(patientID: patient.id, type: type)
        n.updatedAt = Date()
        store.notes.append(n)
        store.lastModified = Date()

        store.selectedNoteID = n.id
        selectedAttachmentID = nil

        if isPhone {
            phonePath.append(.note(n.id))
        }
    }

    private func finalizeSelectedNote() {
        guard let id = store.selectedNoteID,
              let idx = store.notes.firstIndex(where: { $0.id == id }) else { return }

        store.notes[idx].isFinalized = true
        store.notes[idx].finalizedAt = Date()
        store.notes[idx].updatedAt = Date()
        store.lastModified = Date()
    }

    private func deleteCurrentSelection() {
        if let id = store.selectedNoteID {
            store.notes.removeAll(where: { $0.id == id })
            store.selectedNoteID = nil
            store.lastModified = Date()
        } else if let id = selectedAttachmentID {
            store.attachments.removeAll(where: { $0.id == id })
            selectedAttachmentID = nil
            store.lastModified = Date()
        }
    }

    // MARK: - Import (local, iPhone-safe)

    private func importPickedFile(_ url: URL) {
        do {
            let dest = try persistImportedFile(url: url, category: importingCategory)
            let att = Attachment(
                patientID: patient.id,
                category: importingCategory,
                originalFileName: url.lastPathComponent,
                storedFileName: dest.lastPathComponent
            )
            store.attachments.append(att)
            store.lastModified = Date()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let filename = "photo-\(UUID().uuidString).jpg"
            let dest = try persistImportedData(data: data, fileName: filename, category: importingCategory)
            let att = Attachment(
                patientID: patient.id,
                category: importingCategory,
                originalFileName: filename,
                storedFileName: dest.lastPathComponent
            )
            await MainActor.run {
                store.attachments.append(att)
                store.lastModified = Date()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Photo import failed: \(error.localizedDescription)"
            }
        }
    }

    private func attachmentFileURL(_ att: Attachment) -> URL? {
        // We store files in our own Documents subfolder, so this is deterministic.
        // Also tries a few fallback locations in case you already have legacy storage.
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        let preferred = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(att.patientID.uuidString, isDirectory: true)
            .appendingPathComponent(att.category.rawValue, isDirectory: true)
            .appendingPathComponent(att.storedFileName)

        if fm.fileExists(atPath: preferred.path) { return preferred }

        // Fallbacks (legacy)
        let candidates: [URL] = [
            docs.appendingPathComponent(att.storedFileName),
            docs.appendingPathComponent(att.patientID.uuidString).appendingPathComponent(att.storedFileName),
            docs.appendingPathComponent("Attachments").appendingPathComponent(att.storedFileName),
            docs.appendingPathComponent("Attachments").appendingPathComponent(att.patientID.uuidString).appendingPathComponent(att.storedFileName)
        ]
        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private func persistImportedFile(url: URL, category: Attachment.Category) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        let dir = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(patient.id.uuidString, isDirectory: true)
            .appendingPathComponent(category.rawValue, isDirectory: true)

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let ext = url.pathExtension
        let stored = "\(UUID().uuidString)" + (ext.isEmpty ? "" : ".\(ext)")
        let dest = dir.appendingPathComponent(stored)

        // ✅ IMPORTANT: Files app gives security-scoped URLs
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        // Copy in (overwrite if exists)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)

        return dest
    }

    private func persistImportedData(data: Data, fileName: String, category: Attachment.Category) throws -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        let dir = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(patient.id.uuidString, isDirectory: true)
            .appendingPathComponent(category.rawValue, isDirectory: true)

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stored = "\(UUID().uuidString)-\(fileName)"
        let dest = dir.appendingPathComponent(stored)
        try data.write(to: dest, options: [.atomic])
        return dest
    }
}


