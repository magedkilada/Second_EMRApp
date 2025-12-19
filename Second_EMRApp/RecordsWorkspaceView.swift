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

// MARK: - QuickLook preview
fileprivate struct EMRQuickLookPreview: UIViewControllerRepresentable {
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
fileprivate struct EMRShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Print presenter (no SwiftUI sheet => avoids blank flash)
fileprivate struct EMRPrintPresenter: UIViewControllerRepresentable {
    @Binding var printJob: IdentifiableURL?

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard let job = printJob else { return }

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

// MARK: - Records Workspace
struct RecordsWorkspaceView: View {

    // MARK: - Inputs
    @ObservedObject var store: EMRStore
    let patientID: UUID
    let patient: Patient

    // MARK: - Layout
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - Selection
    @State private var selectedAttachmentID: UUID?
    @State private var lastActiveNoteID: UUID? = nil

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

    // MARK: - Batch selection (iPad only)
    private enum BatchKind { case notes, prescriptions }
    @State private var isSelectingForBatch = false
    @State private var batchKind: BatchKind = .notes
    @State private var selectedIDsForBatch: Set<UUID> = []

    // MARK: - Local errors (so we don't require store.lastErrorMessage)
    @State private var errorMessage: String?

    // MARK: - Data
    private var notesForPatient: [RecordNote] {
        store.notes.filter { $0.patientID == patientID }
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
        guard let id = store.selectedNoteID else { return nil }
        return notesForPatient.first(where: { $0.id == id })
    }

    private var selectedAttachment: Attachment? {
        guard let id = selectedAttachmentID else { return nil }
        return attachmentsForPatient.first(where: { $0.id == id })
    }

    private var selectedNoteIsFinalized: Bool { selectedNote?.isFinalized == true }

    // MARK: - Body
    var body: some View {
        Group {
            if isPhone {
                phoneNavigationLayout
            } else {
                ipadSplitLayout
            }
        }
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topRightToolbar }

        // FILE import (single URL)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                importPickedFile(url)
            } catch {
                errorMessage = "Import pick failed: \(error.localizedDescription)"
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

        // SHARE
        .sheet(item: $shareJob) { job in
            EMRShareSheet(items: [job.url])
        }

        // PRINT
        .background(EMRPrintPresenter(printJob: $printJob))

        .onAppear {
            if lastActiveNoteID == nil { lastActiveNoteID = store.selectedNoteID }
        }
    }

    // MARK: - iPhone layout (push navigation)
    private var phoneNavigationLayout: some View {
        NavigationStack {
            recordsListPane_phone
        }
    }

    private var recordsListPane_phone: some View {
        List {

            Section("Notes") {
                ForEach(nonPrescriptions) { note in
                    NavigationLink {
                        if let b = bindingForNote(id: note.id) {
                            NoteEditorView(note: b) { saved in
                                var n = saved
                                n.updatedAt = Date()
                                store.saveNote(n)
                            }
                            .navigationTitle(b.wrappedValue.displayTitle)
                            .onAppear {
                                store.selectedNoteID = note.id
                                selectedAttachmentID = nil
                            }
                        } else {
                            Text("Note not found.")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        noteRow(note)
                    }
                    .listRowBackground(
                        store.selectedNoteID == note.id
                        ? Color.yellow.opacity(0.25)
                        : Color.clear
                    )
                }
            }

            if !prescriptions.isEmpty {
                Section("Prescriptions") {
                    ForEach(prescriptions) { note in
                        NavigationLink {
                            if let b = bindingForNote(id: note.id) {
                                NoteEditorView(note: b) { saved in
                                    var n = saved
                                    n.updatedAt = Date()
                                    store.saveNote(n)
                                }
                                .navigationTitle(b.wrappedValue.displayTitle)
                                .onAppear {
                                    store.selectedNoteID = note.id
                                    selectedAttachmentID = nil
                                }
                            } else {
                                Text("Note not found.")
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            noteRow(note)
                        }
                        .listRowBackground(
                            store.selectedNoteID == note.id
                            ? Color.yellow.opacity(0.25)
                            : Color.clear
                        )
                    }
                }
            }

            Section("Attachments") {
                ForEach(attachmentsForPatient) { att in
                    NavigationLink {
                        attachmentDetail(att)
                            .navigationTitle("Attachment")
                            .onAppear {
                                selectedAttachmentID = att.id
                                store.selectedNoteID = nil
                            }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(att.originalFileName).lineLimit(1)
                            Text(att.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let msg = errorMessage {
                Section {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    // MARK: - iPad layout (split)
    private var ipadSplitLayout: some View {
        HStack(spacing: 0) {
            recordsListPane_ipad
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)

            Divider()

            detailPane_ipad
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var recordsListPane_ipad: some View {
        List {
            Section("Notes") {
                ForEach(nonPrescriptions) { note in
                    rowForNote_ipad(note, kind: .notes)
                        .listRowBackground((lastActiveNoteID == note.id) ? Color.yellow.opacity(0.22) : Color.clear)
                }
            }

            if !prescriptions.isEmpty {
                Section("Prescriptions") {
                    ForEach(prescriptions) { note in
                        rowForNote_ipad(note, kind: .prescriptions)
                            .listRowBackground((lastActiveNoteID == note.id) ? Color.yellow.opacity(0.22) : Color.clear)
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
                        isSelectingForBatch = false
                        selectedIDsForBatch.removeAll()

                        selectedAttachmentID = att.id
                        store.selectedNoteID = nil
                    }
                    .contextMenu {
                        Button("Preview") {
                            previewURL = attachmentURL(att)
                            showPreview = true
                        }
                        Button("Share") { shareAttachment(att) }
                        Button("Print") { printAttachment(att) }

                        Divider()

                        Button(role: .destructive) {
                            deleteAttachment(att)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let msg = errorMessage {
                Section {
                    Text(msg).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rowForNote_ipad(_ note: RecordNote, kind: BatchKind) -> some View {
        HStack(spacing: 12) {

            if isSelectingForBatch, batchKind == kind {
                Image(systemName: selectedIDsForBatch.contains(note.id) ? "checkmark.circle.fill" : "circle")
                    .onTapGesture { toggleBatchSelection(note.id) }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle).font(.body)
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
                store.selectedNoteID = note.id
                lastActiveNoteID = note.id
                selectedAttachmentID = nil
            }
        }
    }

    // MARK: - iPad detail
    private var detailPane_ipad: some View {
        Group {
            if let id = store.selectedNoteID, let b = bindingForNote(id: id) {
                NoteEditorView(note: b) { saved in
                    var n = saved
                    n.updatedAt = Date()
                    store.saveNote(n)
                }
                .navigationTitle(b.wrappedValue.displayTitle)

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

    // MARK: - Rows
    private func noteRow(_ note: RecordNote) -> some View {
        let isSelected = store.selectedNoteID == note.id

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                Text(note.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if note.isFinalized {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.yellow.opacity(0.25) : Color.clear)
        )
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

            Button {
                shareCurrentSelection()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)

            Menu {
                Button("Print Current Selection") { printCurrentSelection() }

                if !isPhone {
                    Divider()
                    Button("Print All Notes") { printBatch(title: "All Notes", notes: nonPrescriptions) }
                        .disabled(nonPrescriptions.isEmpty)

                    Button("Print Prescriptions") { printBatch(title: "Prescriptions", notes: prescriptions) }
                        .disabled(prescriptions.isEmpty)

                    Divider()

                    Button("Select Notes…") { beginBatchSelection(kind: .notes) }
                        .disabled(nonPrescriptions.isEmpty)

                    Button("Select Prescriptions…") { beginBatchSelection(kind: .prescriptions) }
                        .disabled(prescriptions.isEmpty)

                    Button("Print Selected") { printSelectedBatch() }
                        .disabled(!isSelectingForBatch || selectedIDsForBatch.isEmpty)

                    Button("Cancel Selection", role: .destructive) { cancelBatchSelection() }
                        .disabled(!isSelectingForBatch)
                }

            } label: {
                Image(systemName: "printer")
            }

            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)
        }
    }

    // MARK: - Note binding (fixes wrong note content)
    private func bindingForNote(id: UUID) -> Binding<RecordNote>? {
        guard let idx = store.notes.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.notes[idx] },
            set: { store.notes[idx] = $0 }
        )
    }

    // MARK: - Batch selection
    private func beginBatchSelection(kind: BatchKind) {
        isSelectingForBatch = true
        batchKind = kind
        selectedIDsForBatch.removeAll()
        store.selectedNoteID = nil
        selectedAttachmentID = nil
    }

    private func cancelBatchSelection() {
        isSelectingForBatch = false
        selectedIDsForBatch.removeAll()
    }

    private func toggleBatchSelection(_ id: UUID) {
        if selectedIDsForBatch.contains(id) {
            selectedIDsForBatch.remove(id)
        } else {
            selectedIDsForBatch.insert(id)
        }
    }

    private func printSelectedBatch() {
        guard isSelectingForBatch else { return }

        let source: [RecordNote] = (batchKind == .notes) ? nonPrescriptions : prescriptions
        let selected = source.filter { selectedIDsForBatch.contains($0.id) }
        guard !selected.isEmpty else { return }

        let title = (batchKind == .notes) ? "Selected Notes" : "Selected Prescriptions"
        printBatch(title: title, notes: selected)
        cancelBatchSelection()
    }

    // MARK: - Note actions
    private func addNote(type: RecordType) {
        var note = RecordNote(patientID: patientID, type: type)
        note.createdAt = Date()
        note.updatedAt = Date()

        store.addNote(note)
        store.selectedNoteID = note.id
        lastActiveNoteID = note.id
        selectedAttachmentID = nil
    }

    private func finalizeSelectedNote() {
        guard let id = store.selectedNoteID,
              let idx = store.notes.firstIndex(where: { $0.id == id }) else { return }
        if store.notes[idx].isFinalized { return }

        store.notes[idx].isFinalized = true
        store.notes[idx].finalizedAt = Date()
        store.notes[idx].updatedAt = Date()
        store.saveNote(store.notes[idx])
    }

    private func deleteCurrentSelection() {
        if let id = store.selectedNoteID {
            store.deleteNote(id)
            store.selectedNoteID = nil
            return
        }

        if let att = selectedAttachment {
            deleteAttachment(att)
            selectedAttachmentID = nil
            return
        }
    }

    // MARK: - Detail (attachment)
    private func attachmentDetail(_ att: Attachment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(att.originalFileName).font(.headline)
            Text(att.category.rawValue).foregroundStyle(.secondary)

            HStack {
                Button("Preview") {
                    previewURL = attachmentURL(att)
                    showPreview = true
                }
                .buttonStyle(.borderedProminent)

                Button("Share") { shareAttachment(att) }
                    .buttonStyle(.bordered)

                Button("Print") { printAttachment(att) }
                    .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteAttachment(att)
                } label: {
                    Text("Delete")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Share / Print (single)
    @MainActor
    private func shareCurrentSelection() {
        if let id = store.selectedNoteID, let note = selectedNote {
            Task {
                do {
                    let url = try makeNotePDFURL(noteTitle: note.displayTitle, noteText: note.body)
                    shareJob = IdentifiableURL(url: url, jobName: note.displayTitle)
                } catch {
                    errorMessage = "Share failed: \(error.localizedDescription)"
                }
            }
            return
        }

        if let att = selectedAttachment {
            shareAttachment(att)
        }
    }

    @MainActor
    private func printCurrentSelection() {
        if let _ = store.selectedNoteID, let note = selectedNote {
            Task {
                do {
                    let url = try makeNotePDFURL(noteTitle: note.displayTitle, noteText: note.body)
                    printJob = IdentifiableURL(url: url, jobName: note.displayTitle)
                } catch {
                    errorMessage = "Print failed: \(error.localizedDescription)"
                }
            }
            return
        }

        if let att = selectedAttachment {
            printAttachment(att)
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
                errorMessage = "Batch print failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Attachments (local files)
    private func attachmentsDirectory() -> URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Attachments", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func attachmentURL(_ att: Attachment) -> URL {
        attachmentsDirectory().appendingPathComponent(att.storedFileName)
    }

    private func importPickedFile(_ url: URL) {
        let needs = url.startAccessingSecurityScopedResource()
        defer { if needs { url.stopAccessingSecurityScopedResource() } }

        do {
            let originalName = url.lastPathComponent
            let ext = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
            let stored = UUID().uuidString + ext
            let dest = attachmentsDirectory().appendingPathComponent(stored)

            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)

            let newAtt = Attachment(
                patientID: patientID,
                category: importingCategory,
                originalFileName: originalName,
                storedFileName: stored
            )

            store.attachments.insert(newAtt, at: 0)
            store.forcePersistAll()

            selectedAttachmentID = newAtt.id
            store.selectedNoteID = nil

        } catch {
            errorMessage = "Import file failed: \(error.localizedDescription)"
        }
    }

    private func deleteAttachment(_ att: Attachment) {
        let url = attachmentURL(att)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        store.attachments.removeAll { $0.id == att.id }
        store.forcePersistAll()
    }

    private func shareAttachment(_ att: Attachment) {
        let url = attachmentURL(att)
        shareJob = IdentifiableURL(url: url, jobName: att.originalFileName)
    }

    private func printAttachment(_ att: Attachment) {
        let url = attachmentURL(att)
        printJob = IdentifiableURL(url: url, jobName: att.originalFileName)
    }

    // MARK: - Photo import
    private func importPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }

            let tmpURL = try writeTempJPEG(image: image)

            await MainActor.run {
                importPickedFile(tmpURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Photo import failed: \(error.localizedDescription)"
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

    // MARK: - PDF creation (single note)
    private func makeNotePDFURL(noteTitle: String, noteText: String) throws -> URL {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: noteTitle]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
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

                let header = NSAttributedString(string: note.displayTitle, attributes: titleAttrs)
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

// MARK: - Note Editor (Binding<RecordNote> => always edits correct note)
fileprivate struct NoteEditorView: View {
    @Binding var note: RecordNote
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
