import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import QuickLook
import UIKit
import Foundation

// MARK: - Identifiable print/share job
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

// MARK: - Print presenter
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

    // Inputs
    @ObservedObject var store: EMRStore
    let patientID: UUID
    let patient: Patient

    // Layout
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // Physician
    @EnvironmentObject private var physicians: PhysiciansStore

    // Selection
    @State private var selectedAttachmentID: UUID?

    // Import
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?

    // Preview
    @State private var previewURL: URL?
    @State private var showPreview = false

    // Share / Print jobs
    @State private var shareJob: IdentifiableURL?
    @State private var printJob: IdentifiableURL?

    // Errors
    @State private var errorMessage: String?

    // MARK: - Data

    private var patientName: String {
        let n = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Patient" : n
    }

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

    // MARK: - Export Header + Body (for Copy/Share/Print)

    private func exportTextFor(note: RecordNote) -> String {
        let patientName = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Patient"
            : patient.nameEnglish

        let mrn = patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : patient.mrn
        let dob = patient.dob.formatted(date: .numeric, time: .omitted)
        let sex = patient.gender.rawValue
        let phone = patient.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : patient.phone

        let clinic = "Neurosurgery"
        let physician = physicians.selectedPhysicianName ?? "—"

        let created = note.createdAt.formatted(date: .numeric, time: .shortened)
        let updated = note.updatedAt.formatted(date: .numeric, time: .shortened)

        let header = """
Patient: \(patientName)
MRN: \(mrn) | DOB: \(dob) | Sex: \(sex) | Phone: \(phone) | Clinic: \(clinic)
Physician: \(physician)
Note: Created: \(created) | Updated: \(updated)
----------------------------------------

"""

        return header + note.body
    }

    // MARK: - Body
    var body: some View {
        Group {
            if isPhone {
                phoneList
            } else {
                ipadSplit
            }
        }
        .toolbar { topRightToolbar }

        // File import
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

        // Photo import
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, newItem in
            guard let item = newItem else { return }
            Task { await importPickedPhoto(item) }
        }

        // Preview
        .sheet(isPresented: $showPreview) {
            if let url = previewURL {
                EMRQuickLookPreview(url: url)
            }
        }

        // Share
        .sheet(item: $shareJob) { job in
            EMRShareSheet(items: [job.url])
        }

        // Print
        .background(EMRPrintPresenter(printJob: $printJob))
    }

    // MARK: - iPhone list + push

    private var phoneList: some View {
        List {
            Section("Notes") {
                ForEach(nonPrescriptions) { note in
                    NavigationLink {
                        noteEditorDestination(noteID: note.id)
                    } label: {
                        noteRow(note)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        store.selectedNoteID = note.id
                        selectedAttachmentID = nil
                    })
                    .listRowBackground(
                        store.selectedNoteID == note.id ? Color.yellow.opacity(0.25) : Color.clear
                    )
                }
            }

            if !prescriptions.isEmpty {
                Section("Prescriptions") {
                    ForEach(prescriptions) { note in
                        NavigationLink {
                            noteEditorDestination(noteID: note.id)
                        } label: {
                            noteRow(note)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            store.selectedNoteID = note.id
                            selectedAttachmentID = nil
                        })
                        .listRowBackground(
                            store.selectedNoteID == note.id ? Color.yellow.opacity(0.25) : Color.clear
                        )
                    }
                }
            }

            Section("Attachments") {
                ForEach(attachmentsForPatient) { att in
                    NavigationLink {
                        attachmentDetail(att)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Text(patientName).font(.headline).lineLimit(1)
                                }
                            }
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
                Section { Text(msg).font(.footnote).foregroundStyle(.red) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func noteEditorDestination(noteID: UUID) -> some View {
        Group {
            if let b = bindingForNote(id: noteID) {
                NoteEditorView(note: b, patient: patient) { saved in
                    var n = saved
                    n.updatedAt = Date()
                    store.saveNote(n)
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(patientName)
                                .font(.headline)
                                .lineLimit(1)
                            Text(b.wrappedValue.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onAppear {
                    store.selectedNoteID = noteID
                    selectedAttachmentID = nil
                }
            } else {
                Text("Note not found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - iPad split

    private var ipadSplit: some View {
        HStack(spacing: 0) {
            ipadLeftList
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 380)

            Divider()

            ipadRightDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var ipadLeftList: some View {
        List {
            Section("Notes") {
                ForEach(nonPrescriptions) { note in
                    noteRow(note)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectedNoteID = note.id
                            selectedAttachmentID = nil
                        }
                        .listRowBackground(
                            store.selectedNoteID == note.id ? Color.yellow.opacity(0.22) : Color.clear
                        )
                }
            }

            if !prescriptions.isEmpty {
                Section("Prescriptions") {
                    ForEach(prescriptions) { note in
                        noteRow(note)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.selectedNoteID = note.id
                                selectedAttachmentID = nil
                            }
                            .listRowBackground(
                                store.selectedNoteID == note.id ? Color.yellow.opacity(0.22) : Color.clear
                            )
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
                        Button(role: .destructive) { deleteAttachment(att) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let msg = errorMessage {
                Section { Text(msg).font(.footnote).foregroundStyle(.red) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var ipadRightDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(patientName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)

            Divider()

            Group {
                if let id = store.selectedNoteID, let b = bindingForNote(id: id) {
                    NoteEditorView(note: b, patient: patient) { saved in
                        var n = saved
                        n.updatedAt = Date()
                        store.saveNote(n)
                    }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
    }

    // MARK: - Row

    private func noteRow(_ note: RecordNote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                Text(note.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if note.isFinalized {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
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
                copyCurrentSelection()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .disabled(store.selectedNoteID == nil)

            Button {
                shareCurrentSelection()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)

            Button {
                printCurrentSelection()
            } label: {
                Image(systemName: "printer")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)

            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNoteID == nil && selectedAttachmentID == nil)
        }
    }

    // MARK: - Note binding
    private func bindingForNote(id: UUID) -> Binding<RecordNote>? {
        guard let idx = store.notes.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.notes[idx] },
            set: { store.notes[idx] = $0 }
        )
    }

    // MARK: - Note actions
    private func addNote(type: RecordType) {
        var note = RecordNote(patientID: patientID, type: type)
        note.createdAt = Date()
        note.updatedAt = Date()
        store.addNote(note)
        store.selectedNoteID = note.id
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
        if let _ = store.selectedNoteID {
            if let id = store.selectedNoteID { store.deleteNote(id) }
            store.selectedNoteID = nil
            return
        }
        if let att = selectedAttachment {
            deleteAttachment(att)
            selectedAttachmentID = nil
        }
    }

    // MARK: - Copy / Share / Print (header included)
    private func copyCurrentSelection() {
        guard let note = selectedNote else { return }
        UIPasteboard.general.string = exportTextFor(note: note)
        errorMessage = "Copied note to clipboard."
    }

    private func shareCurrentSelection() {
        if let note = selectedNote {
            do {
                let exportText = exportTextFor(note: note)
                let url = try makeNotePDFURL(noteTitle: note.displayTitle, noteText: exportText)
                shareJob = IdentifiableURL(url: url, jobName: note.displayTitle)
            } catch {
                errorMessage = "Share failed: \(error.localizedDescription)"
            }
            return
        }
        if let att = selectedAttachment { shareAttachment(att) }
    }

    private func printCurrentSelection() {
        if let note = selectedNote {
            do {
                let exportText = exportTextFor(note: note)
                let url = try makeNotePDFURL(noteTitle: note.displayTitle, noteText: exportText)
                printJob = IdentifiableURL(url: url, jobName: note.displayTitle)
            } catch {
                errorMessage = "Print failed: \(error.localizedDescription)"
            }
            return
        }
        if let att = selectedAttachment { printAttachment(att) }
    }

    // MARK: - Attachment detail
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

                Button(role: .destructive) { deleteAttachment(att) } label: {
                    Text("Delete")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Attachments storage

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
            await MainActor.run { importPickedFile(tmpURL) }

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

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // letter
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
}
