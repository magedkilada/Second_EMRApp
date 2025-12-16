import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import QuickLook

struct RecordsWorkspaceView: View {

    // MARK: - Inputs
    @ObservedObject var store: EMRStore
    let patientID: UUID
    let patient: Patient

    // MARK: - Selection
    @State private var selectedNoteID: UUID?
    @State private var selectedAttachmentID: UUID?

    // MARK: - Import state
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?

    // MARK: - Preview / Share / Print
    @State private var previewURL: URL?
    @State private var showPreview = false

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    @State private var showPrintSheet = false
    @State private var printJobName: String = "Record"
    @State private var printURL: URL?

    // MARK: - Data
    private var notesForPatient: [RecordNote] {
        store.notes
            .filter { $0.patientID == patientID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var prescriptions: [RecordNote] {
        notesForPatient.filter { $0.type == .prescription }
    }

    private var nonPrescriptions: [RecordNote] {
        notesForPatient.filter { $0.type != .prescription }
    }

    private var attachmentsForPatient: [Attachment] {
        store.attachments
            .filter { $0.patientID == patientID }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private var selectedNote: RecordNote? {
        guard let id = selectedNoteID else { return nil }
        return store.notes.first(where: { $0.id == id })
    }

    private var selectedAttachment: Attachment? {
        guard let id = selectedAttachmentID else { return nil }
        return store.attachments.first(where: { $0.id == id })
    }

    private var selectedNoteIsFinalized: Bool {
        selectedNote?.isFinalized == true
    }

    // MARK: - UI
    var body: some View {
        NavigationSplitView {
            recordsListPane
        } detail: {
            detailPane
        }
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topRightToolbar }   // ✅ ALL actions live here (top-right)

        // FILE import
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let att = store.importFile(patientID: patientID, category: importingCategory, sourceURL: url) {
                    selectedAttachmentID = att.id
                    selectedNoteID = nil
                }
            }
        }

        // PHOTO import (picker UI)
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, newItem in
            guard let item = newItem else { return }
            Task { await importPickedPhoto(item) }
        }

        // PREVIEW
        .sheet(isPresented: $showPreview) {
            if let url = previewURL {
                RSQuickLookPreview(url: url)
            }
        }

        // SHARE
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }

        // PRINT
        .sheet(isPresented: $showPrintSheet) {
            if let url = printURL {
                PrintSheet(jobName: printJobName, fileURL: url)
            }
        }
    }

    // MARK: - LEFT PANE (lists only)
    private var recordsListPane: some View {
        List(selection: Binding(
            get: { selectionTag },
            set: { newTag in applySelection(tag: newTag) }
        )) {

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(patient.nameEnglish.isEmpty ? "Unnamed (English)" : patient.nameEnglish)
                        .font(.headline)
                    if !patient.mrn.isEmpty {
                        Text("MRN: \(patient.mrn)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Prescriptions") {
                if prescriptions.isEmpty {
                    Text("No prescriptions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(prescriptions) { note in
                        RecordRow(title: note.type.headerTitle, date: note.updatedAt, isFinalized: note.isFinalized)
                            .tag(selectionTagForNote(note.id))
                    }
                }
            }

            Section("Notes") {
                if nonPrescriptions.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nonPrescriptions) { note in
                        RecordRow(title: note.type.headerTitle, date: note.updatedAt, isFinalized: note.isFinalized)
                            .tag(selectionTagForNote(note.id))
                    }
                }
            }

            Section("Imported Files & Photos") {
                if attachmentsForPatient.isEmpty {
                    Text("No imported records yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentsForPatient) { att in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(att.originalFileName)
                                .lineLimit(1)
                            Text(att.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(selectionTagForAttachment(att.id))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - RIGHT PANE
    private var detailPane: some View {
        Group {
            if let noteID = selectedNoteID,
               let binding = bindingForNote(noteID) {
                noteEditor(note: binding)

            } else if let att = selectedAttachment {
                attachmentDetail(att)

            } else {
                ContentUnavailableView(
                    "No record selected",
                    systemImage: "doc",
                    description: Text("Select a note or imported file.")
                )
            }
        }
        .padding()
    }

    // MARK: - TOP RIGHT TOOLBAR (actions)
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {

            // Finalize (permanent)
            if selectedNoteID != nil {
                Button {
                    finalizeSelectedNote()
                } label: {
                    Label(selectedNoteIsFinalized ? "Finalized" : "Finalize",
                          systemImage: selectedNoteIsFinalized ? "lock.fill" : "checkmark.seal")
                }
                .disabled(selectedNoteIsFinalized)
            }

            // Add note
            Menu {
                Button("H&P") { addNote(type: .hp) }
                Button("SOAP / Progress Note") { addNote(type: .soap) }
                Button("Operative") { addNote(type: .operative) }
                Button("Discharge") { addNote(type: .discharge) }
                Button("EEG") { addNote(type: .eeg) }
                Button("Prescription") { addNote(type: .prescription) }
                Button("Clinical Note") { addNote(type: .blank) }
            } label: {
                Image(systemName: "square.and.pencil")
            }

            // Import (with category choices for BOTH file and photo)
            // If iPad still refuses to show the Photo submenu on your iOS version,
            // I included a fallback right below (commented) that always works.
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

                // ---- FALLBACK (uncomment if Photo submenu still won’t appear) ----
                /*
                Section("Import File…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showFileImporter = true
                        }
                    }
                }
                Section("Import Photo…") {
                    ForEach(Attachment.Category.allCases) { cat in
                        Button(cat.rawValue) {
                            importingCategory = cat
                            showPhotoPicker = true
                        }
                    }
                }
                */
            } label: {
                Image(systemName: "paperclip")
            }

            // Share
            Button {
                shareCurrentSelection()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(selectedNoteID == nil && selectedAttachmentID == nil)

            // Print
            Button {
                printCurrentSelection()
            } label: {
                Image(systemName: "printer")
            }
            .disabled(selectedNoteID == nil && selectedAttachmentID == nil)

            // Delete (notes only before finalize)
            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(
                (selectedNoteID == nil && selectedAttachmentID == nil) ||
                (selectedNoteID != nil && selectedNoteIsFinalized)
            )
        }
    }

    // MARK: - Note editor
    private func noteEditor(note: Binding<RecordNote>) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text(note.wrappedValue.type.headerTitle)
                    .font(.headline)

                if note.wrappedValue.isFinalized {
                    Spacer()
                    Label("Finalized", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: note.body)
                .frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
                .disabled(note.wrappedValue.isFinalized)

            HStack {
                Button("Save") {
                    var n = note.wrappedValue
                    n.updatedAt = Date()
                    store.saveNote(n)
                }
                .buttonStyle(.borderedProminent)
                .disabled(note.wrappedValue.isFinalized)

                Spacer()
            }

            if note.wrappedValue.isFinalized {
                Text("This note is finalized and cannot be edited or deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Attachment detail
    private func attachmentDetail(_ att: Attachment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(att.originalFileName).font(.headline)
            Text(att.category.rawValue).foregroundStyle(.secondary)

            Button("View") {
                previewURL = store.attachmentFileURL(att)
                showPreview = (previewURL != nil)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions
    private func addNote(type: RecordType) {
        let note = RecordNote(patientID: patientID, type: type)
        store.saveNote(note)
        selectedNoteID = note.id
        selectedAttachmentID = nil
    }

    private func finalizeSelectedNote() {
        guard let id = selectedNoteID,
              let idx = store.notes.firstIndex(where: { $0.id == id }) else { return }

        store.notes[idx].isFinalized = true
        store.notes[idx].finalizedAt = Date()
        store.notes[idx].updatedAt = Date()
        store.saveNote(store.notes[idx])
    }

    private func deleteCurrentSelection() {
        if let id = selectedNoteID,
           let note = store.notes.first(where: { $0.id == id }) {

            guard note.isFinalized == false else { return }
            store.deleteNote(note)
            selectedNoteID = nil

        } else if let id = selectedAttachmentID,
                  let att = store.attachments.first(where: { $0.id == id }) {
            store.deleteAttachment(att)
            selectedAttachmentID = nil
        }
    }

    private func shareCurrentSelection() {
        if let note = selectedNote {
            if let url = SharePrintBuilder.makePDFFile(
                filename: "Note",
                title: note.type.headerTitle,
                body: note.body
            ) {
                shareItems = [url]
            } else {
                shareItems = [note.body]
            }
            showShareSheet = true
            return
        }

        if let att = selectedAttachment {
            shareItems = [store.attachmentFileURL(att)]
            showShareSheet = true
        }
    }

    private func printCurrentSelection() {
        if let note = selectedNote,
           let url = SharePrintBuilder.makePDFFile(
                filename: "Note",
                title: note.type.headerTitle,
                body: note.body
           ) {
            printJobName = note.type.headerTitle
            printURL = url
            showPrintSheet = true
            return
        }

        if let att = selectedAttachment {
            printJobName = att.originalFileName
            printURL = store.attachmentFileURL(att)
            showPrintSheet = true
        }
    }

    /// Photo import WITHOUT `store.importPhoto`:
    /// Save picked image to a temp .jpg, then call your existing `store.importFile(...)`.
    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Photo-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        do {
            try data.write(to: tempURL, options: .atomic)

            if let att = store.importFile(patientID: patientID, category: importingCategory, sourceURL: tempURL) {
                await MainActor.run {
                    selectedAttachmentID = att.id
                    selectedNoteID = nil
                    pickedPhoto = nil
                }
            }
        } catch {
            await MainActor.run {
                pickedPhoto = nil
            }
        }
    }

    // MARK: - Binding helpers
    private func bindingForNote(_ id: UUID) -> Binding<RecordNote>? {
        guard let idx = store.notes.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.notes[idx] },
            set: { store.notes[idx] = $0 }
        )
    }

    // MARK: - Tagged selection plumbing
    private enum SelectionTag: Hashable {
        case note(UUID)
        case attachment(UUID)
    }

    private var selectionTag: SelectionTag? {
        if let n = selectedNoteID { return .note(n) }
        if let a = selectedAttachmentID { return .attachment(a) }
        return nil
    }

    private func applySelection(tag: SelectionTag?) {
        switch tag {
        case .note(let id):
            selectedNoteID = id
            selectedAttachmentID = nil
        case .attachment(let id):
            selectedAttachmentID = id
            selectedNoteID = nil
        case nil:
            selectedNoteID = nil
            selectedAttachmentID = nil
        }
    }

    private func selectionTagForNote(_ id: UUID) -> SelectionTag { .note(id) }
    private func selectionTagForAttachment(_ id: UUID) -> SelectionTag { .attachment(id) }
}

// MARK: - Row UI (lock badge)
private struct RecordRow: View {
    let title: String
    let date: Date
    let isFinalized: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isFinalized {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - QuickLook
private struct RSQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
