import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import QuickLook
import UIKit

// MARK: - Identifiable print/share job (file scope)
fileprivate struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
    let jobName: String
}

struct RecordsWorkspaceView: View {

    // MARK: - Inputs
    @ObservedObject var store: EMRStore
    let patientID: UUID
    let patient: Patient

    // MARK: - Selection
    @State private var selectedNoteID: UUID?
    @State private var selectedAttachmentID: UUID?
    @State private var showAIAssist = false

    // MARK: - Import
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?

    // MARK: - Preview
    @State private var previewURL: URL?
    @State private var showPreview = false

    // MARK: - Share / Print jobs
    @State private var shareJob: IdentifiableURL?
    @State private var printJob: IdentifiableURL?

    // MARK: - Batch selection
    private enum BatchKind {
        case notes
        case prescriptions
    }
    @State private var isSelectingForBatch = false
    @State private var batchKind: BatchKind = .notes
    @State private var selectedIDsForBatch: Set<UUID> = []

    // MARK: - Data
    private var notesForPatient: [RecordNote] { store.notes(for: patientID) }

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
        return notesForPatient.first(where: { $0.id == id })
    }

    private var selectedAttachment: Attachment? {
        guard let id = selectedAttachmentID else { return nil }
        return attachmentsForPatient.first(where: { $0.id == id })
    }

    private var selectedNoteIsFinalized: Bool { selectedNote?.isFinalized == true }

    // MARK: - UI
    var body: some View {
        HStack(spacing: 0) {

            // LEFT LIST
            recordsListPane
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)

            Divider()

            // RIGHT DETAIL
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topRightToolbar }

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

        // PHOTO import
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, newItem in
            guard let item = newItem else { return }
            Task { await importPickedPhoto(item) }
        }

        // PREVIEW
        .sheet(isPresented: $showPreview) {
            if let url = previewURL {
                EMRQuickLookPreview(url: url)
            }
        }
        
        .sheet(isPresented: $showAIAssist) {
            if let note = selectedNote {
                AIAssistView(note: note) { newBody in
                    var n = note
                    n.body = newBody
                    n.updatedAt = Date()
                    store.saveNote(n)
                }
            } else {
                Text("No note selected.")
                    .padding()
            }
        }

        // SHARE (only when URL is ready)
        .sheet(item: $shareJob) { job in
            EMRShareSheet(items: [job.url])
        }

        // PRINT (UIKit presenter — avoids SwiftUI blank flash)
        .background(EMRPrintPresenter(printJob: $printJob))
    }

    
    // MARK: - Left pane (list)
    private var recordsListPane: some View {
        List {

            Section("Notes") {
                ForEach(nonPrescriptions) { note in
                    rowForNote(note, kind: .notes)
                }
            }

            if !prescriptions.isEmpty {
                Section("Prescriptions") {
                    ForEach(prescriptions) { note in
                        rowForNote(note, kind: .prescriptions)
                    }
                }
            }

            Section("Attachments") {
                ForEach(attachmentsForPatient) { att in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(att.originalFileName).lineLimit(1)
                            Text(att.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // attachments are not part of batch-selection
                        isSelectingForBatch = false
                        selectedIDsForBatch.removeAll()

                        selectedAttachmentID = att.id
                        selectedNoteID = nil
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rowForNote(_ note: RecordNote, kind: BatchKind) -> some View {
        HStack(spacing: 12) {

            // selection circles ONLY when selecting and only for matching section
            if isSelectingForBatch, batchKind == kind {
                Image(systemName: selectedIDsForBatch.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.blue)
                    .onTapGesture { toggleBatchSelection(note.id) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(note.type.headerTitle).font(.body)
                Text(note.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if note.isFinalized {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectingForBatch, batchKind == kind {
                toggleBatchSelection(note.id)
            } else {
                selectedNoteID = note.id
                selectedAttachmentID = nil
            }
        }
    }

    private func toggleBatchSelection(_ id: UUID) {
        if selectedIDsForBatch.contains(id) {
            selectedIDsForBatch.remove(id)
        } else {
            selectedIDsForBatch.insert(id)
        }
    }

    // MARK: - Detail pane
    private var detailPane: some View {
        Group {
            if let note = selectedNote {
                NoteEditorView(note: note) { saveNote($0) }
                    .navigationTitle(note.type.headerTitle)

            } else if let att = selectedAttachment {
                attachmentDetail(att)

            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a note or attachment from the list.")
                )
            }
        }
        .padding()
    }

    private func attachmentDetail(_ att: Attachment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(att.originalFileName)
                .font(.headline)

            Text(att.category.rawValue)
                .foregroundStyle(.secondary)

            Button("Preview") {
                previewURL = attachmentURL(att)
                showPreview = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {

        ToolbarItemGroup(placement: .topBarTrailing) {

            // Finalize
            if selectedNoteID != nil {
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

            // Add note
            Menu {
                Button("H&P")          { addNote(type: .hp) }
                Button("SOAP")         { addNote(type: .soap) }
                Button("Operative")    { addNote(type: .operative) }
                Button("Discharge")    { addNote(type: .discharge) }
                Button("EEG")          { addNote(type: .eeg) }
                Button("Prescription") { addNote(type: .prescription) }
                Button("Clinical Note"){ addNote(type: .blank) }
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

            // Share
            Button {
                shareCurrentSelection()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(selectedNoteID == nil && selectedAttachmentID == nil)// AI Assist (only when a note is selected)
            if selectedNoteID != nil {
                Button {
                    showAIAssist = true
                } label: {
                    Image(systemName: "sparkles")
                }
            }
            
            

            // PRINT (single + batch + selectable batch) from ONE button
            Menu {
                Button("Print Current Selection") { printCurrentSelection() }

                Divider()

                Button("Print All Notes") { printBatch(title: "All Notes", notes: nonPrescriptions) }
                    .disabled(nonPrescriptions.isEmpty)

                Button("Print Prescriptions") { printBatch(title: "Prescriptions", notes: prescriptions) }
                    .disabled(prescriptions.isEmpty)

                Divider()

                Button("Select Notes…") {
                    beginBatchSelection(kind: .notes)
                }
                .disabled(nonPrescriptions.isEmpty)

                Button("Select Prescriptions…") {
                    beginBatchSelection(kind: .prescriptions)
                }
                .disabled(prescriptions.isEmpty)

                Button("Print Selected") {
                    printSelectedBatch()
                }
                .disabled(!isSelectingForBatch || selectedIDsForBatch.isEmpty)

                Button("Cancel Selection", role: .destructive) {
                    cancelBatchSelection()
                }
                .disabled(!isSelectingForBatch)

            } label: {
                Image(systemName: "printer")
            }
            .disabled(selectedNoteID == nil && selectedAttachmentID == nil && nonPrescriptions.isEmpty && prescriptions.isEmpty)

            // Delete
            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedNoteID == nil && selectedAttachmentID == nil)
        }
    }

    private func beginBatchSelection(kind: BatchKind) {
        isSelectingForBatch = true
        batchKind = kind
        selectedIDsForBatch.removeAll()
        selectedNoteID = nil
        selectedAttachmentID = nil
    }

    private func cancelBatchSelection() {
        isSelectingForBatch = false
        selectedIDsForBatch.removeAll()
    }

    private func printSelectedBatch() {
        guard isSelectingForBatch else { return }

        let source: [RecordNote] = (batchKind == .notes) ? nonPrescriptions : prescriptions
        let selected = source.filter { selectedIDsForBatch.contains($0.id) }

        guard !selected.isEmpty else { return }

        let title = (batchKind == .notes) ? "Selected Notes" : "Selected Prescriptions"
        printBatch(title: title, notes: selected)

        // optional: auto-exit selection mode after printing
        cancelBatchSelection()
    }

    // MARK: - Note actions
    private func addNote(type: RecordType) {
        var note = RecordNote(patientID: patientID, type: type)

        // If this is a blank note, ensure it has a usable title
        if type == .blank, note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note.title = "Clinical Note"
        }

        note.createdAt = Date()
        note.updatedAt = Date()
        store.saveNote(note)

        selectedNoteID = note.id
        selectedAttachmentID = nil
    }

    private func saveNote(_ note: RecordNote) {
        var n = note
        n.updatedAt = Date()
        store.saveNote(n)
    }

    private func finalizeSelectedNote() {
        guard var note = selectedNote else { return }
        guard note.isFinalized == false else { return }

        note.isFinalized = true
        note.finalizedAt = Date()
        note.updatedAt = Date()
        store.saveNote(note)
    }

    private func deleteCurrentSelection() {
        // If you're in batch-selection mode, do nothing here (prevents accidental deletes)

        if let note = selectedNote {
            store.deleteNote(note)
            selectedNoteID = nil
            return
        }

        if let att = selectedAttachment {
            store.deleteAttachment(att)
            selectedAttachmentID = nil
            return
        }
    }

    // MARK: - Share / Print (single)
    @MainActor
    private func shareCurrentSelection() {
        if let note = selectedNote {
            Task {
                do {
                    let url = try makeNotePDFURL(noteTitle: note.type.headerTitle, noteText: note.body)
                    shareJob = IdentifiableURL(url: url, jobName: note.type.headerTitle)
                } catch {
                    store.lastErrorMessage = "Share failed: \(error.localizedDescription)"
                }
            }
            return
        }

        if let att = selectedAttachment {
            shareJob = IdentifiableURL(url: attachmentURL(att), jobName: att.category.rawValue)
        }
    }

    @MainActor
    private func printCurrentSelection() {
        if let note = selectedNote {
            Task {
                do {
                    let url = try makeNotePDFURL(noteTitle: note.type.headerTitle, noteText: note.body)
                    printJob = IdentifiableURL(url: url, jobName: note.type.headerTitle)
                } catch {
                    store.lastErrorMessage = "Print failed: \(error.localizedDescription)"
                }
            }
            return
        }

        if let att = selectedAttachment {
            printJob = IdentifiableURL(url: attachmentURL(att), jobName: att.category.rawValue)
        }
    }

    // MARK: - Print (batch)
    @MainActor
    private func printBatch(title: String, notes: [RecordNote]) {
        guard !notes.isEmpty else { return }

        Task {
            do {
                let url = try makeBatchPDFURL(title: title, notes: notes)
                printJob = IdentifiableURL(url: url, jobName: title)
            } catch {
                store.lastErrorMessage = "Batch print failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Photo import
    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }

            let tmpURL = try writeTempJPEG(image: image)

            if let att = store.importFile(patientID: patientID, category: importingCategory, sourceURL: tmpURL) {
                await MainActor.run {
                    selectedAttachmentID = att.id
                    selectedNoteID = nil
                }
            }
        } catch {
            await MainActor.run {
                store.lastErrorMessage = "Photo import failed: \(error.localizedDescription)"
            }
        }
    }

    private func writeTempJPEG(image: UIImage) throws -> URL {
        guard let jpg = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "EMR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode JPEG"])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try jpg.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Attachment URL (matches your store helper)
    private func attachmentURL(_ att: Attachment) -> URL {
        store.attachmentFileURL(att)
    }

    // MARK: - PDF creation (single note)
    private func makeNotePDFURL(noteTitle: String, noteText: String) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: noteTitle]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let margin: CGFloat = 36
            var y: CGFloat = margin

            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18)]
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]

            let title = NSAttributedString(string: noteTitle, attributes: titleAttrs)
            let titleSize = title.boundingRect(
                with: CGSize(width: pageRect.width - 2 * margin, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            ).integral.size

            title.draw(in: CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: titleSize.height))
            y += titleSize.height + 16

            let body = NSAttributedString(string: noteText, attributes: bodyAttrs)
            let bodyRect = CGRect(x: margin, y: y,
                                  width: pageRect.width - 2 * margin,
                                  height: pageRect.height - y - margin)
            body.draw(in: bodyRect)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - PDF creation (batch) — one note per page
    private func makeBatchPDFURL(title: String, notes: [RecordNote]) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            let margin: CGFloat = 36
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 16)]
            let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]

            for note in notes.sorted(by: { $0.updatedAt > $1.updatedAt }) {
                ctx.beginPage()
                var y: CGFloat = margin

                let header = NSAttributedString(string: note.type.headerTitle, attributes: titleAttrs)
                let headerSize = header.boundingRect(
                    with: CGSize(width: pageRect.width - 2 * margin, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).integral.size

                header.draw(in: CGRect(x: margin, y: y,
                                       width: pageRect.width - 2 * margin,
                                       height: headerSize.height))
                y += headerSize.height + 12

                let body = NSAttributedString(string: note.body, attributes: bodyAttrs)
                let bodyRect = CGRect(x: margin, y: y,
                                      width: pageRect.width - 2 * margin,
                                      height: pageRect.height - y - margin)
                body.draw(in: bodyRect)
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Minimal Note Editor
private struct NoteEditorView: View {
    @State var note: RecordNote
    let onSave: (RecordNote) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $note.body)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .disabled(note.isFinalized)

            HStack {
                Button("Save") {
                    var n = note
                    n.updatedAt = Date()
                    onSave(n)
                    note = n
                }
                .buttonStyle(.borderedProminent)
                .disabled(note.isFinalized)

                if note.isFinalized {
                    Text("This note is finalized and cannot be edited or deleted.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                Spacer()
            }
        }
    }
}

// MARK: - QuickLook preview
private struct EMRQuickLookPreview: UIViewControllerRepresentable {
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

// MARK: - Share sheet
private struct EMRShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Print presenter (no SwiftUI sheet => no blank flash)
private struct EMRPrintPresenter: UIViewControllerRepresentable {
    @Binding var printJob: IdentifiableURL?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard let job = printJob else { return }

        // clear first to prevent double present
        DispatchQueue.main.async { self.printJob = nil }

        DispatchQueue.main.async {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = job.jobName
            info.outputType = .general

            controller.printInfo = info
            controller.printingItem = job.url
            controller.present(animated: true, completionHandler: nil)
        }
    }
}
