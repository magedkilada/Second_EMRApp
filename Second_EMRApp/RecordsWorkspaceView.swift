//
//  RecordsWorkspaceView.swift
//  Second_EMRApp
//

import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import QuickLook
import UIKit

// ✅ commit notification used by NoteEditorView autosave before switching selection
extension Notification.Name {
    static let emrCommitNoteEdits = Notification.Name("emr.commitNoteEdits")
}

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

    // MARK: - Sheets
    @State private var showBatchPrint = false
    @State private var showTemplatePicker = false
    @State private var showReferenceCenter = false

    // MARK: - Alerts
    @State private var errorMessage: String? = nil
    @State private var confirmDeleteAttachmentID: UUID? = nil

    // MARK: - QuickLook
    @State private var previewURL: URL? = nil
    @State private var showPreview = false

    // MARK: - Body
    var body: some View {
        Group {
            if isPhone {
                phoneNavigationLayout
            } else {
                ipadTwoPaneLayout   // ✅ no nested NavigationSplitView
            }
        }
        .toolbar { importOnlyToolbar }

        // Batch Print
        .sheet(isPresented: $showBatchPrint) {
            BatchPrintView(patient: patient)
                .environmentObject(store)
        }

        // References Center
        .sheet(isPresented: $showReferenceCenter) {
            ReferencesCenterView()
        }

        // Template picker
        .sheet(isPresented: $showTemplatePicker) {
            templatePickerSheet
        }

        // Photo picker
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

        // File importer
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

        // Import error
        .alert("Import failed", isPresented: Binding(
            get: { lastAttachmentImportError != nil },
            set: { if !$0 { lastAttachmentImportError = nil } }
        )) {
            Button("OK", role: .cancel) { lastAttachmentImportError = nil }
        } message: {
            Text(lastAttachmentImportError ?? "")
        }

        // Generic error
        .alert("Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }

        // ✅ Attachment delete confirmation
        .alert("Delete attachment?", isPresented: Binding(
            get: { confirmDeleteAttachmentID != nil },
            set: { if !$0 { confirmDeleteAttachmentID = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDeleteAttachmentID = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteAttachmentID {
                    deleteAttachment(id)
                }
                confirmDeleteAttachmentID = nil
            }
        } message: {
            Text("This will remove the attachment file from this device.")
        }

        // QuickLook preview
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

    // MARK: - iPad Two-Pane Layout (NO nested NavigationSplitView)
    private var ipadTwoPaneLayout: some View {
        HStack(spacing: 0) {
            recordsList
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            Divider()

            recordsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Medical Records")
    }

    // MARK: - iPhone Layout
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

    // MARK: - List
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
                            commitCurrentEditorIfNeeded()
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
                        commitCurrentEditorIfNeeded()
                        showTemplatePicker = true
                    } label: {
                        Image(systemName: "plus")
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
                            commitCurrentEditorIfNeeded()
                            selectedAttachmentID = a.id
                            store.selectedNoteID = nil
                            if isPhone { phonePath.append(.attachment(a.id)) }
                        } label: {
                            attachmentRow(a)
                        }
                        // ✅ optional swipe-to-delete (with warning)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                confirmDeleteAttachmentID = a.id
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Attachments")
            }
        }
    }

    // MARK: - Detail (Attachment has bottom-right actions; Note stays in NoteEditorView)
    private var recordsDetail: some View {
        Group {
            if let noteID = store.selectedNoteID {
                noteEditorDestination(noteID: noteID)
                    .id(noteID)

            } else if let attID = selectedAttachmentID,
                      let att = attachmentByID(attID),
                      let url = attachmentFileURL(att) {

                AttachmentDetailPanel(
                    patientName: patientName,
                    attachment: att,
                    fileURL: url,
                    onOpenPreview: {
                        previewURL = url
                        showPreview = true
                    },
                    onShare: {
                        PrintShareHelper.shareURL(url, title: "Attachment")
                    },
                    onPrint: {
                        printFileURL(url) // ✅ safe even if helper lacks printFile
                    },
                    onBatchPrint: {
                        showBatchPrint = true
                    },
                    onDelete: {
                        confirmDeleteAttachmentID = att.id
                    }
                )

            } else {
                ContentUnavailableView("Select a note or attachment", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Toolbar (IMPORT ONLY)
    @ToolbarContentBuilder
    private var importOnlyToolbar: some ToolbarContent {
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

    // MARK: - Template Picker Sheet
    private var templatePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(RecordType.allCases) { type in
                    Button {
                        showTemplatePicker = false
                        addNote(type: type)
                    } label: {
                        HStack {
                            Image(systemName: iconForRecordType(type))
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 40)

                            Text(type.headerTitle)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showTemplatePicker = false }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showReferenceCenter = true } label: {
                        Label("References", systemImage: "book")
                    }
                }
            }
        }
    }

    // MARK: - Rows
    private func noteRow(_ n: RecordNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(n.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if n.isFinalized {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
            if store.notes.first(where: { $0.id == noteID }) != nil {
                NoteEditorView(patient: patient, noteID: noteID)
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

                AttachmentDetailPanel(
                    patientName: patientName,
                    attachment: att,
                    fileURL: url,
                    onOpenPreview: {
                        previewURL = url
                        showPreview = true
                    },
                    onShare: {
                        PrintShareHelper.shareURL(url, title: "Attachment")
                    },
                    onPrint: {
                        printFileURL(url)
                    },
                    onBatchPrint: {
                        showBatchPrint = true
                    },
                    onDelete: {
                        confirmDeleteAttachmentID = att.id
                    }
                )

            } else {
                Text("Attachment not found.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Data + Search
    private var patientNotes: [RecordNote] {
        store.notes
            .filter { $0.patientID == patient.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var patientAttachments: [Attachment] {
        store.attachments
            .filter { $0.patientID == patient.id }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private var filteredNotes: [RecordNote] {
        let q = recordsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return patientNotes }
        return patientNotes.filter { n in
            let hay = [n.displayTitle, n.type.rawValue, n.body].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    private var filteredAttachments: [Attachment] {
        let q = recordsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return patientAttachments }
        return patientAttachments.filter { a in
            let hay = [a.category.rawValue, a.originalFileName, a.storedFileName].joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    // MARK: - Commit before switching
    private func commitCurrentEditorIfNeeded() {
        guard let currentID = store.selectedNoteID else { return }
        NotificationCenter.default.post(
            name: .emrCommitNoteEdits,
            object: nil,
            userInfo: ["noteID": currentID]
        )
    }

    // MARK: - Add Note (Template)
    private func addNote(type: RecordType) {
        commitCurrentEditorIfNeeded()

        var n = RecordNote(patientID: patient.id, type: type)
        n.updatedAt = Date()

        store.notes.insert(n, at: 0)
        store.saveNotes()

        store.selectedNoteID = n.id
        selectedAttachmentID = nil

        if isPhone { phonePath.append(.note(n.id)) }
    }

    private func iconForRecordType(_ type: RecordType) -> String {
        switch type {
        case .hp: return "doc.text"
        case .soap: return "note.text"
        case .operative: return "bandage"
        case .discharge: return "arrow.right.square"
        case .eeg: return "waveform.path.ecg"
        case .prescription: return "pills"
        case .blank: return "doc.plaintext"
        }
    }

    // MARK: - Attachments helpers
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

    private func deleteAttachment(_ id: UUID) {
        guard let att = store.attachments.first(where: { $0.id == id }) else { return }

        if let url = attachmentFileURL(att) {
            try? FileManager.default.removeItem(at: url)
        }

        store.attachments.removeAll(where: { $0.id == id })
        store.saveAttachments()

        if selectedAttachmentID == id {
            selectedAttachmentID = nil
        }
    }

    // MARK: - Share/Print helpers
    private func printFileURL(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        controller.printingItem = url
        controller.present(animated: true, completionHandler: nil)
    }

    // MARK: - Import
    private func importPickedFile(_ url: URL, category: Attachment.Category) throws {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

        let dest = try persistImportedFile(url: url, category: category)

        let att = Attachment(
            patientID: patient.id,
            category: category,
            originalFileName: url.lastPathComponent,
            storedFileName: dest.lastPathComponent
        )

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

    // MARK: - Patient Name
    private var patientName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Patient"
    }
}

// MARK: - Attachment detail panel with bottom-right actions (including Delete)
private struct AttachmentDetailPanel: View {
    let patientName: String
    let attachment: Attachment
    let fileURL: URL

    let onOpenPreview: () -> Void
    let onShare: () -> Void
    let onPrint: () -> Void
    let onBatchPrint: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {

            VStack(alignment: .leading, spacing: 6) {
                Text(patientName)
                    .font(.title2).bold()

                Text(attachment.originalFileName.isEmpty ? "Attachment" : attachment.originalFileName)
                    .font(.headline)

                Text(attachment.category.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            Divider()

            Button {
                onOpenPreview()
            } label: {
                Label("Open Preview", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Spacer()

            // ✅ Bottom-right action row (ONE batch button + Trash)
            HStack(spacing: 14) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)

                Button(action: onPrint) {
                    Image(systemName: "printer")
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)

                Button(action: onBatchPrint) {
                    Image(systemName: "tray.full")
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
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

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

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
