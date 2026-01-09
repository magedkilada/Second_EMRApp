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
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - iPhone Navigation
    enum PhoneRoute: Hashable {
        case note(UUID)
        case attachment(UUID)
    }
    @State private var phonePath: [PhoneRoute] = []

    // MARK: - Selection
    @State private var selectedAttachmentID: UUID? = nil
    @State private var recordsSearchText: String = ""

    // MARK: - Import UI
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showAttachmentImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var lastAttachmentImportError: String? = nil
    
    @State private var showBatchPrint = false

    // MARK: - Errors
    @State private var errorMessage: String? = nil

    // MARK: - QuickLook
    @State private var previewURL: URL? = nil
    @State private var showPreview = false
    
    // MARK: - Print (Single)

    private func printSingleSelected() {
        // If a note is selected, print the note text
        if let noteID = store.selectedNoteID,
           let note = store.notes.first(where: { $0.id == noteID }) {
            PrintShareHelper.printText(composedText(for: note))
            return
        }

        // If an attachment is selected, print the file (PDF/image/etc)
        if let attID = selectedAttachmentID,
           let att = store.attachments.first(where: { $0.id == attID }),
           let url = attachmentFileURL(att) {
            printURL(url)
            return
        }
    }

    /// Include header in single-print (patient + title + dates)
    private func composedText(for note: RecordNote) -> String {
        var lines: [String] = []

        // Header
        lines.append(patientName)
        lines.append(note.displayTitle)
        lines.append(note.type.rawValue)
        lines.append("Updated: \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")
        lines.append(note.body)

        return lines.joined(separator: "\n")
    }

    /// Local file printing helper (works even if PrintShareHelper has no printFile)
    private func printURL(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
    }

    
    // MARK: - Body
    private var recordsWorkspaceBody: some View {
        Group {
            if isPhone {
                phoneNavigationLayout
            } else {
                ipadSplitLayout
            }
        }
        .toolbar { topRightToolbar }
        .sheet(isPresented: $showBatchPrint) {
               BatchPrintView(patient: patient)
                   .environmentObject(store)
           }
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
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                try importPickedFile(url, category: importingCategory)
            } catch {
                lastAttachmentImportError = error.localizedDescription
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { lastAttachmentImportError != nil },
            set: { if !$0 { lastAttachmentImportError = nil } }
        )) {
            Button("OK", role: .cancel) { lastAttachmentImportError = nil }
        } message: {
            Text(lastAttachmentImportError ?? "")
        }
        .sheet(isPresented: $showPreview) {
            if let url = previewURL {
                QuickLookPreview(url: url)
            } else {
                Text("No preview.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
    // MARK: - Layouts
    
    var body: some View {
        recordsWorkspaceBody
    }

    private var ipadSplitLayout: some View {
        NavigationSplitView {
            recordsList
                .navigationTitle("Medical Records")
        } detail: {
            recordsDetail
                .navigationTitle(patientName)
        }
    }

    private var phoneNavigationLayout: some View {
        NavigationStack(path: $phonePath) {
            recordsList
                .navigationTitle("Medical Records")
                .navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case .note(let id):
                        noteEditorDestination(noteID: id)
                    case .attachment(let id):
                        attachmentDestination(attachmentID: id)
                    }
                }
        }
    }

    // MARK: - List + Detail

    private var recordsList: some View {
        List {
            // Search
            Section {
                TextField("Search notes & attachments…", text: $recordsSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            // Notes
            Section {
                if filteredNotes.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredNotes) { n in
                        Button {
                            store.selectedNoteID = n.id
                            selectedAttachmentID = nil
                            if isPhone { phonePath.append(.note(n.id)) }
                        } label: {
                            noteRow(n)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Notes")
                    Spacer()
                    Button {
                        addNote()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Attachments
            Section {
                if filteredAttachments.isEmpty {
                    ContentUnavailableView("No attachments", systemImage: "paperclip")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAttachments) { a in
                        Button {
                            selectedAttachmentID = a.id
                            store.selectedNoteID = nil
                            if isPhone { phonePath.append(.attachment(a.id)) }
                        } label: {
                            attachmentRow(a)
                        }
                    }
                }
            } header: {
                Text("Attachments")
            }
        }
    }

    private var recordsDetail: some View {
        Group {
            if let noteID = store.selectedNoteID {
                noteEditorDestination(noteID: noteID)
            } else if let attID = selectedAttachmentID {
                attachmentDestination(attachmentID: attID)
            } else {
                ContentUnavailableView("Select a note or attachment", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    
    
    // MARK: - Toolbar
    
    
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {

            Menu {
                // Photos
                Button {
                    importingCategory = .radiology
                    showPhotoPicker = true
                } label: { Label("Import Photo → Radiology", systemImage: "photo") }

                Button {
                    importingCategory = .laboratory
                    showPhotoPicker = true
                } label: { Label("Import Photo → Laboratory", systemImage: "photo") }

                Button {
                    importingCategory = .specialTest
                    showPhotoPicker = true
                } label: { Label("Import Photo → Special Test", systemImage: "photo") }

                Button {
                    importingCategory = .medicalReport
                    showPhotoPicker = true
                } label: { Label("Import Photo → Medical Report", systemImage: "photo") }

                Divider()

                // Files
                Button {
                    importingCategory = .radiology
                    showAttachmentImporter = true
                } label: { Label("Import File → Radiology", systemImage: "folder") }

                Button {
                    importingCategory = .laboratory
                    showAttachmentImporter = true
                } label: { Label("Import File → Laboratory", systemImage: "folder") }

                Button {
                    importingCategory = .specialTest
                    showAttachmentImporter = true
                } label: { Label("Import File → Special Test", systemImage: "folder") }

                Button {
                    importingCategory = .medicalReport
                    showAttachmentImporter = true
                } label: { Label("Import File → Medical Report", systemImage: "folder") }

            } label: {
                Image(systemName: "square.and.arrow.down.on.square")
            }
        }
    }
    // MARK: - Rows

    private func noteRow(_ n: RecordNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(n.displayTitle)
                .font(.headline)
                .lineLimit(1)

            Text(n.type.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        
    }

    private func attachmentRow(_ a: Attachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(a.originalFileName.isEmpty ? "Attachment" : a.originalFileName)
                    .font(.headline)
                    .lineLimit(1)

                Text(a.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Destinations

    private func noteEditorDestination(noteID: UUID) -> some View {
        Group {
            if let binding = bindingForNote(id: noteID) {
                // IMPORTANT: This matches your current NoteEditorView initializer
                NoteEditorView(
                    patient: patient,
                    noteID: noteID
                )
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
                    Text(att.originalFileName.isEmpty ? "Attachment" : att.originalFileName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(att.category.rawValue)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button {
                        previewURL = url
                        showPreview = true
                    } label: {
                        Label("Open Preview", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding()

            } else {
                Text("Attachment not found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Data (per patient) + Smart Search

    private var patientNotes: [RecordNote] {
        store.notes.filter { $0.patientID == patient.id }
    }

    private var patientAttachments: [Attachment] {
        store.attachments.filter { $0.patientID == patient.id }
    }

    private var filteredNotes: [RecordNote] {
        let q = recordsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return patientNotes }

        return patientNotes.filter { n in
            let hay = [
                n.displayTitle,
                n.type.rawValue,
                n.body
            ].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    private var filteredAttachments: [Attachment] {
        let q = recordsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return patientAttachments }

        return patientAttachments.filter { a in
            let hay = [
                a.category.rawValue,
                a.originalFileName,
                a.storedFileName
            ].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    // MARK: - Helpers (notes)

    private func bindingForNote(id: UUID) -> Binding<RecordNote>? {
        guard let idx = store.notes.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.notes[idx]
    }

    private func addNote() {
        var n = RecordNote(patientID: patient.id, type: .soap)
        n.updatedAt = Date()
        store.notes.insert(n, at: 0)
        store.saveNotes()

        store.selectedNoteID = n.id
        selectedAttachmentID = nil

        if isPhone { phonePath.append(.note(n.id)) }
    }

    // MARK: - Helpers (attachments)

    private func attachmentByID(_ id: UUID) -> Attachment? {
        store.attachments.first(where: { $0.id == id })
    }

    private func attachmentFileURL(_ att: Attachment) -> URL? {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

        let url = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(patient.id.uuidString, isDirectory: true)
            .appendingPathComponent(att.category.rawValue, isDirectory: true)
            .appendingPathComponent(att.storedFileName)

        return fm.fileExists(atPath: url.path) ? url : nil
    }

    
    // MARK: - Share / Print (Top menu actions)

    private func shareCurrentNote() {
        // If a note is selected, share note text
        if let noteID = store.selectedNoteID,
           let note = store.notes.first(where: { $0.id == noteID }) {
            let text = composedText(for: note)
            PrintShareHelper.shareText(text, title: "Medical Record")
            return
        }

        // If an attachment is selected, share attachment file URL (if you want)
        if let attID = selectedAttachmentID,
           let att = attachmentByID(attID),
           let url = attachmentFileURL(att) {
            PrintShareHelper.shareURL(url, title: "Attachment")
            return
        }

        // Nothing selected
        errorMessage = "Select a note or attachment first."
    }

    private func printCurrentNote() {
        // If a note is selected, print note text
        if let noteID = store.selectedNoteID,
           let note = store.notes.first(where: { $0.id == noteID }) {
            let text = composedText(for: note)
            PrintShareHelper.printText(text, jobName: "Medical Record")
            return
        }

        // If an attachment is selected, print the file (PDF/image)
        if let attID = selectedAttachmentID,
           let att = attachmentByID(attID),
           let url = attachmentFileURL(att) {
            PrintShareHelper.printFile(url, jobName: "Attachment")
            return
        }
        // Nothing selected
        errorMessage = "Select a note or attachment first."
        
    }
    // MARK: - Import / Preview Helpers

    private func importPickedFile(_ url: URL, category: Attachment.Category) throws {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        // Copy into sandbox
        let dest = try persistImportedFile(url: url, category: category)

        // Create attachment model
        let att = Attachment(
            patientID: patient.id,
            category: category,
            originalFileName: url.lastPathComponent,
            storedFileName: dest.lastPathComponent
        )

        // Save
        store.attachments.insert(att, at: 0)
        store.saveAttachments()

        selectedAttachmentID = att.id
        store.selectedNoteID = nil

        previewURL = dest
        showPreview = true

        if isPhone { phonePath.append(.attachment(att.id)) }
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

        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: url, to: dest)

        return dest
    }

    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!

            let dir = docs
                .appendingPathComponent("EMR_Attachments", isDirectory: true)
                .appendingPathComponent(patient.id.uuidString, isDirectory: true)
                .appendingPathComponent(importingCategory.rawValue, isDirectory: true)

            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let dest = dir.appendingPathComponent("\(UUID().uuidString).jpg")
            try data.write(to: dest, options: [.atomic])

            let att = Attachment(
                patientID: patient.id,
                category: importingCategory,
                originalFileName: "Photo.jpg",
                storedFileName: dest.lastPathComponent
            )

            store.attachments.insert(att, at: 0)
            store.saveAttachments()

            selectedAttachmentID = att.id
            store.selectedNoteID = nil

            previewURL = dest
            showPreview = true

            if isPhone { phonePath.append(.attachment(att.id)) }

        } catch {
            lastAttachmentImportError = error.localizedDescription
        }
    }

    // MARK: - Small UI helpers

    private var patientName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Patient"
    }
}

// MARK: - QuickLook wrapper

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
