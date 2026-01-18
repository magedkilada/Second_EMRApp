//  RecordsWorkspaceView.swift
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct RecordsWorkspaceView: View {

    let patient: Patient
    @EnvironmentObject private var store: EMRStore

    // MARK: - Search (notes + attachments)
    @State private var recordSearch: String = ""

    // MARK: - Notes delete confirm
    @State private var noteToDelete: RecordNote? = nil
    @State private var showDeleteNoteConfirm: Bool = false

    // MARK: - Attachment delete confirm
    @State private var attachmentToDelete: Attachment? = nil
    @State private var showDeleteAttachmentConfirm: Bool = false

    // MARK: - Preview (QuickLook)
    private struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var previewItem: PreviewItem? = nil

    // MARK: - Vitals editor + delete confirm
    @State private var showVitalsEditor: Bool = false
    @State private var editingVitalID: UUID? = nil

    @State private var vitalToDelete: VitalsEntry? = nil
    @State private var showDeleteVitalConfirm: Bool = false

    // MARK: - Add attachment flow (source -> category -> picker)
    private enum PendingImportSource { case file, photo }

    @State private var showPickSource: Bool = false
    @State private var showPickCategory: Bool = false
    @State private var pendingImportSource: PendingImportSource? = nil
    @State private var pendingCategory: Attachment.Category = .radiology

    // pickers
    @State private var showFileImporter: Bool = false
    @State private var showPhotosPicker: Bool = false
    @State private var photoItem: PhotosPickerItem? = nil

    // MARK: - Normalization
    private func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var q: String {
        norm(recordSearch.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Derived data
    private var patientNotes: [RecordNote] {
        let base = store.notes
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted(by: { $0.updatedAt > $1.updatedAt })

        guard !q.isEmpty else { return base }

        return base.filter { n in
            norm(n.displayTitle).contains(q) ||
            norm(n.type.rawValue).contains(q) ||
            norm(n.body).contains(q)
        }
    }

    private var patientAttachments: [Attachment] {
        let base = store.attachments
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted(by: { $0.importedAt > $1.importedAt })

        guard !q.isEmpty else { return base }

        return base.filter { a in
            norm(a.originalFileName).contains(q) ||
            norm(a.storedFileName).contains(q) ||
            norm(a.category.rawValue).contains(q)
        }
    }

    private var patientVitals: [VitalsEntry] {
        store.vitals
            .filter { $0.patientID == patient.id }
            .sorted { $0.measuredAt > $1.measuredAt }
    }

    private var latestVitals: VitalsEntry? {
        patientVitals.first
    }

    // MARK: - Vitals helpers
    private func bindingForVital(id: UUID) -> Binding<VitalsEntry>? {
        guard let idx = store.vitals.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.vitals[idx]
    }

    private func vitalsTitle(_ v: VitalsEntry) -> String {
        if let bp = v.bpString { return "BP \(bp)" }
        return "Vitals"
    }

    private func vitalsTrailing(_ v: VitalsEntry) -> String {
        let parts: [String?] = [
            v.heartRate.map { "HR \($0)" },
            v.spo2.map { "SpO₂ \($0)%" },
            v.tempC.map { String(format: "T %.1f°C", $0) }
        ]
        return parts.compactMap { $0 }.joined(separator: " • ")
    }

    private func addBlankVitals() {
        var v = VitalsEntry(patientID: patient.id)
        v.measuredAt = Date()
        store.vitals.insert(v, at: 0)

        // keep if exists in your EMRStore; otherwise comment it out
        store.saveVitals()

        editingVitalID = v.id
        showVitalsEditor = true
    }

    // MARK: - Import helpers
    private func importAttachmentFromURL(_ url: URL, category: Attachment.Category) {
        store.importAttachment(from: url, patientID: patient.id, category: category)
    }

    @MainActor
    private func importPhotoItem(_ item: PhotosPickerItem, category: Attachment.Category) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                store.importPhotoData(data, patientID: patient.id, category: category, fileExtension: "jpg")
            }
        } catch {
            store.lastErrorMessage = "Photo import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - SMART VITALS TEXT (includes BMI + HeadCirc)
    private func vitalsOneLine(_ v: VitalsEntry) -> String {
        var chunks: [String] = []

        let dt = v.measuredAt.formatted(date: .abbreviated, time: .shortened)
        chunks.append("Vitals (\(dt)):")

        if let bp = v.bpString { chunks.append("BP \(bp)") }
        if let hr = v.heartRate { chunks.append("HR \(hr)") }
        if let s = v.spo2 { chunks.append("SpO₂ \(s)%") }
        if let t = v.tempC { chunks.append(String(format: "T %.1f°C", t)) }
        if let w = v.weightKg { chunks.append(String(format: "Wt %.1f kg", w)) }
        if let h = v.heightCm { chunks.append(String(format: "Ht %.0f cm", h)) }
        if let bmi = v.bmi, bmi.isFinite { chunks.append(String(format: "BMI %.1f", bmi)) }
        if let hc = v.headCircumferenceCm { chunks.append(String(format: "HC %.1f cm", hc)) }

        return chunks.joined(separator: " • ")
    }

    // Insert vitals under the right section if it exists
    private func smartInsertVitals(_ vitalsLine: String, into body: String) -> String {
        let candidates = [
            "PHYSICAL EXAMINATION:",
            "PHYSICAL EXAM:",
            "OBJECTIVE:",
            "VITALS:",
            "EXAM:"
        ]

        // find earliest occurrence (in the order above)
        for key in candidates {
            if let range = body.range(of: key, options: [.caseInsensitive]) {
                // insert after that line (after the key + newline if present)
                // Find end of that line
                let afterKeyIndex = range.upperBound
                let tail = body[afterKeyIndex...]
                if let newline = tail.firstIndex(of: "\n") {
                    let insertPos = body.index(afterKeyIndex, offsetBy: body.distance(from: afterKeyIndex, to: newline) + 1)
                    var out = body
                    out.insert(contentsOf: vitalsLine + "\n", at: insertPos)
                    return out
                } else {
                    // key exists but no newline after it -> append newline + vitals
                    return body + "\n" + vitalsLine + "\n"
                }
            }
        }

        // fallback: append at end
        return body + "\n" + vitalsLine + "\n"
    }

    private func insertLatestVitalsIntoCurrentNote() {
        guard let v = latestVitals else {
            store.lastErrorMessage = "No vitals found to insert."
            return
        }
        guard let noteID = store.selectedNoteID,
              let idx = store.notes.firstIndex(where: { $0.id == noteID }) else {
            store.lastErrorMessage = "Open a note first, then tap Insert Latest Vitals."
            return
        }

        let line = vitalsOneLine(v)
        store.notes[idx].updatedAt = Date()
        store.saveNotes()

        // ✅ Force immediate refresh of the open editor (so you don't need to reopen)
        let current = noteID
        store.selectedNoteID = nil
        DispatchQueue.main.async {
            store.selectedNoteID = current
        }
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 0) {
            leftPane
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            Divider()

            rightPane
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("Medical Records")
        .navigationBarTitleDisplayMode(.inline)

        // 1) Pick attachment source
        .confirmationDialog("Add attachment",
                            isPresented: $showPickSource,
                            titleVisibility: .visible) {
            Button("Choose File (PDF / etc.)") {
                pendingImportSource = .file
                showPickCategory = true
            }
            Button("Choose Photo") {
                pendingImportSource = .photo
                showPickCategory = true
            }
            Button("Cancel", role: .cancel) { }
        }

        // 2) Pick category
        .confirmationDialog("Category",
                            isPresented: $showPickCategory,
                            titleVisibility: .visible) {
            ForEach(Attachment.Category.allCases, id: \.self) { cat in
                Button(cat.rawValue) {
                    pendingCategory = cat
                    if pendingImportSource == .file {
                        showFileImporter = true
                    } else {
                        showPhotosPicker = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }

        // 3a) Files
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text, .rtf, .html, .data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                importAttachmentFromURL(url, category: pendingCategory)
            } catch {
                store.lastErrorMessage = "Import failed: \(error.localizedDescription)"
            }
        }

        // 3b) Photos
        .sheet(isPresented: $showPhotosPicker) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Pick Photo").font(.title3)
            }
            .padding()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importPhotoItem(newItem, category: pendingCategory)
                showPhotosPicker = false
                photoItem = nil
            }
        }

        // Preview (QuickLook)
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }

        // Vitals Editor (only one sheet)
        .sheet(isPresented: $showVitalsEditor) {
            if let id = editingVitalID, let binding = bindingForVital(id: id) {
                VitalsEditorView(vital: binding) {
                    store.saveVitals()
                }
            } else {
                Text("Vitals not found").padding()
            }
        }

        // Notes delete alert
        .alert("Delete note?", isPresented: $showDeleteNoteConfirm) {
            Button("Delete", role: .destructive) {
                guard let n = noteToDelete,
                      let idx = store.notes.firstIndex(where: { $0.id == n.id }) else { return }
                store.notes[idx].isDeleted = true
                store.saveNotes()
                if store.selectedNoteID == n.id { store.selectedNoteID = nil }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: {
            Text("This will remove the note from the list (soft delete).")
        }

        // Attachments delete alert
        .alert("Delete attachment?", isPresented: $showDeleteAttachmentConfirm) {
            Button("Delete", role: .destructive) {
                guard let a = attachmentToDelete,
                      let idx = store.attachments.firstIndex(where: { $0.id == a.id }) else { return }
                store.attachments[idx].isDeleted = true
                store.saveAttachments()
                if store.selectedAttachmentID == a.id { store.selectedAttachmentID = nil }
                attachmentToDelete = nil
            }
            Button("Cancel", role: .cancel) { attachmentToDelete = nil }
        } message: {
            Text("This will remove the attachment from the list (soft delete).")
        }

        // Vitals delete alert
        .alert("Delete vital entry?", isPresented: $showDeleteVitalConfirm) {
            Button("Delete", role: .destructive) {
                guard let v = vitalToDelete else { return }
                store.vitals.removeAll(where: { $0.id == v.id })
                store.saveVitals()
                if store.selectedVitalID == v.id { store.selectedVitalID = nil }
                vitalToDelete = nil
            }
            Button("Cancel", role: .cancel) { vitalToDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - LEFT PANE
    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(patient.nameEnglish.isEmpty ? "Unnamed Patient" : patient.nameEnglish)
                            .font(.headline)

                        if !patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("MRN: \(patient.mrn)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search").font(.headline)

                        TextField("Search notes / attachments", text: $recordSearch)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                notesBox
                vitalsBox
                attachmentsBox
            }
            .padding()
        }
    }

    // MARK: - Notes box
    private var notesBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Notes").font(.headline)
                    Spacer()

                    Menu {
                        ForEach(RecordNoteType.allCases) { t in
                            Button(t.rawValue) { createNewNote(type: t) }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if patientNotes.isEmpty {
                    Text("No notes yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    VStack(spacing: 8) {
                        ForEach(patientNotes) { n in
                            Button {
                                store.selectedNoteID = n.id
                                store.selectedAttachmentID = nil
                                store.selectedVitalID = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.type.rawValue)
                                            .font(.body.weight(.semibold))

                                        Text(n.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(store.selectedNoteID == n.id
                                              ? Color.blue.opacity(0.18)
                                              : Color(UIColor.secondarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    noteToDelete = n
                                    showDeleteNoteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vitals box (delete uses contextMenu + alert; swipeActions not reliable in VStack)
    private var vitalsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vitals").font(.headline)
                    Spacer()

                    Button { addBlankVitals() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if patientVitals.isEmpty {
                    Text("No vitals yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    VStack(spacing: 8) {
                        ForEach(patientVitals) { v in
                            Button {
                                store.selectedVitalID = v.id
                                store.selectedNoteID = nil
                                store.selectedAttachmentID = nil

                                editingVitalID = v.id
                                showVitalsEditor = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vitalsTitle(v))
                                            .font(.body.weight(.semibold))

                                        Text(v.measuredAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    let trailing = vitalsTrailing(v)
                                    if !trailing.isEmpty {
                                        Text(trailing)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    // Optional visible trash button (if you like)
                                    Button(role: .destructive) {
                                        vitalToDelete = v
                                        showDeleteVitalConfirm = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 6)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(store.selectedVitalID == v.id
                                              ? Color.blue.opacity(0.18)
                                              : Color(UIColor.secondarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    vitalToDelete = v
                                    showDeleteVitalConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Attachments box
    private var attachmentsBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Attachments").font(.headline)
                    Spacer()

                    Button { showPickSource = true } label: {
                        Image(systemName: "paperclip")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                if patientAttachments.isEmpty {
                    Text("No attachments yet")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    VStack(spacing: 8) {
                        ForEach(patientAttachments) { a in
                            Button {
                                store.selectedAttachmentID = a.id
                                store.selectedNoteID = nil
                                store.selectedVitalID = nil

                                let url = store.attachmentFileURL(a)
                                if FileManager.default.fileExists(atPath: url.path) {
                                    previewItem = PreviewItem(url: url)
                                } else {
                                    store.lastErrorMessage = "File missing: \(url.lastPathComponent)"
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "paperclip")
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.originalFileName.isEmpty ? a.storedFileName : a.originalFileName)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(1)

                                        Text(a.category.rawValue)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(a.importedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(store.selectedAttachmentID == a.id
                                              ? Color.blue.opacity(0.18)
                                              : Color(UIColor.secondarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    attachmentToDelete = a
                                    showDeleteAttachmentConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Right Pane
    private var rightPane: some View {
        Group {
            if let noteID = store.selectedNoteID {
                NoteEditorView(patient: patient, noteID: noteID)

            } else if let attID = store.selectedAttachmentID {
                attachmentDetail(attID)
            } else {
                ContentUnavailableView("Select an item", systemImage: "doc.text.magnifyingglass")
            }
        }
        .padding()
    }

    private func attachmentDetail(_ attID: UUID) -> some View {
        let a = store.attachments.first(where: { $0.id == attID && !$0.isDeleted })

        return VStack(alignment: .leading, spacing: 10) {
            Text("Attachment")
                .font(.title2).bold()

            if let a {
                Text(a.originalFileName.isEmpty ? a.storedFileName : a.originalFileName)
                    .font(.headline)

                Text("Category: \(a.category.rawValue)")
                    .foregroundStyle(.secondary)

                Text("Imported: \(a.importedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)

                Divider()

                Text("Use the bottom buttons: Preview / Share / Print.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Attachment not found", systemImage: "questionmark.folder")
            }

            Spacer()
        }
    }

    // MARK: - Actions
    private func createNewNote(type: RecordNoteType) {
        var note = RecordNote(patientID: patient.id, type: type)

        if type.rawValue == "Blank" {
            note.title = ""
            note.body = ""
        }

        store.notes.append(note)
        store.saveNotes()

        store.selectedNoteID = note.id
        store.selectedAttachmentID = nil
        store.selectedVitalID = nil
    }
}
