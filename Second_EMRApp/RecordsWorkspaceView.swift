
//
//  RecordsWorkspaceView.swift
//  Second_EMRApp
//

import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import PhotosUI

struct RecordsWorkspaceView: View {
    let patient: Patient

    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    // MARK: - Local UI state
    @State private var showNewNoteSheet = false
    @State private var workingVitals: SmartVitalsEntry?

    @State private var selectedNoteID: UUID? = nil
    @State private var selectedAttachmentID: UUID? = nil

    // Warning dialogs
    @State private var showSwitchNoteWarning = false
    @State private var pendingNoteID: UUID? = nil

    // Attachment flow
    @State private var showAttachmentSourceMenu = false
    @State private var pendingAttachmentCategory: AttachmentType = .medicalReport
    @State private var showCategoryPicker = false
    @State private var attachmentSourceIsPhotos = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    enum SearchScope: String, CaseIterable, Identifiable {
        case thisPatient = "This Patient"
        case global = "Global"
        var id: String { rawValue }
    }

    @State private var recordSearchText: String = ""
    @State private var searchScope: SearchScope = .thisPatient

    enum LeftPanelMode: String {
        case notes
        case attachments
    }
    @State private var leftPanelMode: LeftPanelMode = .notes

    // MARK: - Derived data

    private var notesForPatient: [RecordNote] {
        store.notes
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var attachmentsForPatient: [Attachment] {
        store.attachments
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var vitalsForPatient: [SmartVitalsEntry] {
        store.vitals
            .filter { $0.patientID == patient.id }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var filteredNotes: [RecordNote] {
        let q = norm(recordSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return notesForPatient }
        return notesForPatient.filter {
            norm($0.displayTitle).contains(q) || norm($0.body).contains(q)
        }
    }

    private var filteredGlobalNotes: [RecordNote] {
        let q = norm(recordSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }
        return store.notes
            .filter { !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { norm($0.displayTitle).contains(q) || norm($0.body).contains(q) }
    }

    private var filteredAttachments: [Attachment] {
        let q = norm(recordSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return attachmentsForPatient }

        return attachmentsForPatient.filter {
            norm($0.filename).contains(q) ||
            norm($0.type.rawValue).contains(q)
        }
    }

    @Environment(\.horizontalSizeClass) private var hSize
    private var isCompact: Bool { hSize == .compact }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isCompact {
                    compactRecordsBody
                } else {
                    HStack(spacing: 0) {
                        leftRecordsPanel
                            .frame(minWidth: 320, maxWidth: 420)
                            .frame(maxHeight: .infinity)

                        Divider()

                        rightEditorPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Records")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            leftPanelMode = .notes
                            selectedAttachmentID = nil
                        } label: { Label("Notes", systemImage: "doc.text") }

                        Button {
                            leftPanelMode = .attachments
                            selectedNoteID = nil
                        } label: { Label("Attachments", systemImage: "paperclip") }
                    } label: {
                        Image(systemName: leftPanelMode == .attachments ? "paperclip" : "doc.text")
                    }
                }
            }
            .sheet(isPresented: $showNewNoteSheet) { noteTypePickerSheet }
            .sheet(item: $workingVitals) { entry in
                vitalsEntrySheet(entry: entry)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: true
            ) { result in
                handleAttachmentImport(result)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                handlePhotoImport(newItems)
            }
            .confirmationDialog("Attachment Source", isPresented: $showAttachmentSourceMenu) {
                Button("Files") {
                    attachmentSourceIsPhotos = false
                    showCategoryPicker = true
                }
                Button("Photos") {
                    attachmentSourceIsPhotos = true
                    showCategoryPicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Attachment Category", isPresented: $showCategoryPicker) {
                Button("Medical Report") { pendingAttachmentCategory = .medicalReport; openPicker() }
                Button("Radiology") { pendingAttachmentCategory = .radiology; openPicker() }
                Button("Laboratory") { pendingAttachmentCategory = .laboratory; openPicker() }
                Button("Special Tests (EEG etc.)") { pendingAttachmentCategory = .eeg; openPicker() }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: selectedNoteID) { _, _ in
                autoDeleteEmptyNote(selectedNoteID)
            }
            .alert("Switch Note?", isPresented: $showSwitchNoteWarning) {
                Button("Save & Switch") {
                    selectedNoteID = pendingNoteID
                    pendingNoteID = nil
                }
                Button("Delete & Switch", role: .destructive) {
                    if let currentID = selectedNoteID { store.deleteNote(currentID) }
                    selectedNoteID = pendingNoteID
                    pendingNoteID = nil
                }
                Button("Cancel", role: .cancel) { pendingNoteID = nil }
            } message: {
                Text("Current note has content. Save it before switching, or delete it?")
            }
        }
    }

    // MARK: - Compact (iPhone) Body

    private var compactRecordsBody: some View {
        VStack(spacing: 0) {
            leftRecordsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationDestination(item: $selectedNoteID) { noteID in
            if let idx = store.notes.firstIndex(where: { $0.id == noteID }) {
                let binding = Binding<RecordNote>(
                    get: { store.notes[idx] },
                    set: { store.saveNote($0) }
                )
                VStack(spacing: 0) {
                    headerBar(note: store.notes[idx])
                    Divider()
                    NoteEditorView(
                        note: binding,
                        patient: patient,
                        onSave: { store.saveNote($0) }
                    )
                    .environmentObject(store)
                    .environmentObject(physicians)
                }
                .inlineNavigationTitle()
            }
        }
        .navigationDestination(item: $selectedAttachmentID) { attachmentID in
            if let att = store.attachments.first(where: { $0.id == attachmentID }) {
                AttachmentPreviewPane(patient: patient, attachment: att) {
                    // Perform delete, then pop after a tick so SwiftUI processes it
                    store.softDeleteAttachment(attachmentID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        selectedAttachmentID = nil
                    }
                }
                .inlineNavigationTitle()
            }
        }
    }

    // MARK: - Panels

    private var leftRecordsPanel: some View {
        VStack(spacing: 12) {
            topActionButtons

            VStack(spacing: 8) {
                Picker("", selection: $searchScope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField("Search records...", text: $recordSearchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 12)

            Group {
                if leftPanelMode == .notes {
                    notesListWithVitals
                } else {
                    attachmentsList
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 4)
        .background(Color.systemGroupedBg)
    }

    private var topActionButtons: some View {
        HStack(spacing: 14) {
            recordActionBtn(title: "Add Note", icon: "doc.badge.plus", color: .blue) { showNewNoteSheet = true }
            recordActionBtn(title: "Add Vitals", icon: "waveform.path.ecg", color: .green) { openNewVitalsEntry() }
            recordActionBtn(title: "Attachments", icon: "paperclip", color: .orange) { showAttachmentSourceMenu = true }
        }
        .padding(.horizontal, 12)
    }

    private func recordActionBtn(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 26, weight: .semibold))
                Text(title).font(.footnote).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(color.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var notesListWithVitals: some View {
        List {
            if !vitalsForPatient.isEmpty {
                Section("Recent Vitals") {
                    ForEach(Array(vitalsForPatient.prefix(5)), id: \.id) { entry in
                        Button {
                            workingVitals = entry
                        } label: { VitalsHistoryRow(entry: entry) }
                        .buttonStyle(.plain)
                    }
                }
            }

            if searchScope == .global, !recordSearchText.isEmpty {
                Section("Global Results") {
                    ForEach(filteredGlobalNotes) { note in
                        Button { selectNote(note.id) } label: { NoteRow(note: note) }
                    }
                }
            }

            Section("This Patient") {
                ForEach(filteredNotes) { note in
                    Button { selectNote(note.id) } label: { NoteRow(note: note) }
                }
            }
        }
        .listStyle(.plain)
    }

    private var attachmentsList: some View {
        List(filteredAttachments) { att in
            Button {
                selectedAttachmentID = att.id
                selectedNoteID = nil
                leftPanelMode = .attachments
            } label: {
                AttachmentRow(attachment: att)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private var rightEditorPanel: some View {
        Group {
            if let noteID = selectedNoteID,
               let idx = store.notes.firstIndex(where: { $0.id == noteID }) {

                let binding = Binding<RecordNote>(
                    get: { store.notes[idx] },
                    set: { store.saveNote($0) }
                )

                VStack(spacing: 0) {
                    headerBar(note: store.notes[idx])
                    Divider()
                    NoteEditorView(
                        note: binding,
                        patient: patient,
                        onSave: { store.saveNote($0) }
                    )
                    .environmentObject(store)
                    .environmentObject(physicians)
                }

            } else if let attachmentID = selectedAttachmentID,
                      let att = store.attachments.first(where: { $0.id == attachmentID }) {

                AttachmentPreviewPane(patient: patient, attachment: att) {
                    store.softDeleteAttachment(attachmentID)
                    selectedAttachmentID = nil
                }

            } else {
                emptyState
            }
        }
        .background(Color.secondarySystemGroupedBg)
    }

    private func headerBar(note: RecordNote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(patient.nameEnglish.isEmpty ? "Unnamed Patient" : patient.nameEnglish)
                    .font(.title2).bold()

                if let age = patient.ageString {
                    Text("\(age) \u{2022} \(patient.gender.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("MRN: \(patient.mrn)")
                    .font(.caption).bold()
                Text(note.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBg)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Select a note or attachment")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Use the buttons on the left to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheets

    private var noteTypePickerSheet: some View {
        NavigationStack {
            List(RecordType.allCases) { type in
                Button {
                    createNewNote(type: type)
                    showNewNoteSheet = false
                } label: {
                    Label(type.headerTitle, systemImage: "doc.text")
                }
            }
            .navigationTitle("New Note")
        }
        .presentationDetents([.medium])
    }

    private func vitalsEntrySheet(entry: SmartVitalsEntry) -> some View {
        SmartVitalsEntrySheet(
            patient: patient,
            vitals: Binding(
                get: { workingVitals ?? entry },
                set: { workingVitals = $0 }
            ),
            onCancel: { workingVitals = nil },
            onInsertIntoNote: { saved in
                store.addOrUpdateVitals(saved)
                autoInsertVitalsIntoLatestNote(saved)
                workingVitals = nil
            },
            onSaveOnly: { saved in
                store.addOrUpdateVitals(saved)
                workingVitals = nil
            }
        )
        .environmentObject(store)
    }

    // MARK: - Logic

    private func selectNote(_ noteID: UUID) {
        if let currentID = selectedNoteID, currentID != noteID, hasUnsavedChanges(currentID) {
            pendingNoteID = noteID
            showSwitchNoteWarning = true
        } else {
            selectedNoteID = noteID
            selectedAttachmentID = nil
            leftPanelMode = .notes
        }
    }

    private func hasUnsavedChanges(_ noteID: UUID) -> Bool {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return false }
        let currentBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentBody.isEmpty && currentBody != note.type.defaultBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoDeleteEmptyNote(_ noteID: UUID?) {
        guard let id = noteID,
              let note = store.notes.first(where: { $0.id == id }) else { return }
        if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.deleteNote(id)
        }
    }

    private func openNewVitalsEntry() {
        workingVitals = SmartVitalsEntry(patientID: patient.id)
    }

    private func createNewNote(type: RecordType) {
        let note = RecordNote(patientID: patient.id, type: type)
        store.addNote(note)
        selectedNoteID = note.id
        selectedAttachmentID = nil
        leftPanelMode = .notes
    }

    private func openPicker() {
        if attachmentSourceIsPhotos {
            showPhotoPicker = true
        } else {
            showFileImporter = true
        }
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                var att = Attachment(patientID: patient.id, type: pendingAttachmentCategory)
                att.filename = url.lastPathComponent
                att.fileURL = url
                store.addAttachment(att)
                selectedAttachmentID = att.id
            }
            leftPanelMode = .attachments
            selectedNoteID = nil
        }
    }

    private func handlePhotoImport(_ items: [PhotosPickerItem]) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data {
                    DispatchQueue.main.async {
                        let filename = "Photo_\(Date().formatted(date: .numeric, time: .shortened)).jpg"
                            .replacingOccurrences(of: "/", with: "-")
                            .replacingOccurrences(of: ":", with: "-")
                            .replacingOccurrences(of: " ", with: "_")
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(filename)
                        try? data.write(to: tempURL)

                        var att = Attachment(patientID: patient.id, type: pendingAttachmentCategory)
                        att.filename = filename
                        att.fileURL = tempURL
                        store.addAttachment(att)
                        selectedAttachmentID = att.id
                        leftPanelMode = .attachments
                        selectedNoteID = nil
                    }
                }
            }
        }
        selectedPhotoItems = []
    }

    private func autoInsertVitalsIntoLatestNote(_ vitals: SmartVitalsEntry) {
        // Find the most recent non-finalized note for this patient
        guard let idx = store.notes.firstIndex(where: {
            $0.patientID == patient.id && !$0.isDeleted && !$0.isFinalized
        }) else { return }

        let vitalsText = "\n" + vitals.formattedBlockCompact(patient: patient, useAI: false) + "\n"
        var lines = store.notes[idx].body.components(separatedBy: "\n")

        let keywords = ["physical examination", "objective", "exam:", "examination:", "pe:", "o:"]
        var insertAt: Int?
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if keywords.contains(where: { lower.contains($0) || lower.hasPrefix($0) }) {
                insertAt = i + 1
                break
            }
        }

        if let at = insertAt, at <= lines.count {
            lines.insert(vitalsText, at: at)
        } else {
            lines.append(vitalsText)
        }

        store.notes[idx].body = lines.joined(separator: "\n")
        store.saveNote(store.notes[idx])
    }
}

// MARK: - Row Subviews

private struct VitalsHistoryRow: View {
    let entry: SmartVitalsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).bold()
                .foregroundStyle(.blue)

            Text(entry.formattedBlock(includePercentiles: false, isUnder5: false))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondarySystemGroupedBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct NoteRow: View {
    let note: RecordNote
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if note.isFinalized {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(note.body)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondarySystemGroupedBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AttachmentRow: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: attachment.type.iconName)
                .foregroundStyle(attachment.type.displayColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text(attachment.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.secondarySystemGroupedBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AttachmentPreviewPane: View {
    let patient: Patient
    let attachment: Attachment
    let onDelete: () -> Void

    @State private var showQuickLook = false
    @State private var showDeleteConfirm = false
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: attachment.type.iconName)
                .font(.system(size: 64))
                .foregroundStyle(attachment.type.displayColor)

            Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                .font(.title3).bold()

            Text(attachment.type.rawValue)
                .font(.subheadline).foregroundStyle(.secondary)

            if hSize == .compact {
                // Vertical layout for iPhone
                VStack(spacing: 12) {
                    attachmentActionButtons
                }
            } else {
                HStack(spacing: 16) {
                    attachmentActionButtons
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showQuickLook) {
            if let url = attachment.fileURL {
                QuickLookPreview(url: url)
            } else {
                Text("No file URL available.")
                    .padding()
            }
        }
        .alert("Delete Attachment?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(attachment.filename.isEmpty ? "this attachment" : attachment.filename)\". This cannot be undone.")
        }
    }

    @ViewBuilder
    private var attachmentActionButtons: some View {
        Button {
            showQuickLook = true
        } label: {
            Label("Preview", systemImage: "eye")
                .frame(minWidth: 100)
        }
        .buttonStyle(.borderedProminent)

        Button {
            shareAttachment()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(minWidth: 100)
        }
        .buttonStyle(.bordered)

        Button {
            printAttachment()
        } label: {
            Label("Print", systemImage: "printer")
                .frame(minWidth: 100)
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
                .frame(minWidth: 100)
        }
        .buttonStyle(.bordered)
    }

    private func shareAttachment() {
        guard let url = attachment.fileURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SharePrintPresenter.share(items: [url])
        }
    }

    private func printAttachment() {
        guard let url = attachment.fileURL else { return }
        SharePrintPresenter.printURL(url, jobName: attachment.filename)
    }
}

// MARK: - AttachmentType UI helpers

private extension AttachmentType {
    var iconName: String {
        switch self {
        case .radiology: return "photo.fill"
        case .laboratory: return "drop.triangle.fill"
        case .eeg: return "waveform.path.ecg"
        case .medicalReport: return "doc.text.fill"
        case .other: return "paperclip"
        }
    }

    var displayColor: Color {
        switch self {
        case .radiology: return .blue
        case .laboratory: return .red
        case .eeg: return .purple
        case .medicalReport: return .orange
        case .other: return .gray
        }
    }
}
