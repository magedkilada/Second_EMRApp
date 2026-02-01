
//
//  RecordsWorkspaceView.swift
//  Second_EMRApp
//

import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import PhotosUI
import PDFKit

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

    // Left panel shows all sections (vitals, notes, attachments) together

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
            .sheet(isPresented: $showNewNoteSheet) { noteTypePickerSheet }
            .sheet(item: $workingVitals) { entry in
                vitalsEntrySheet(entry: entry)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image, .data],
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
            // Attachment source/category dialogs removed — handled by inline Menu on paperclip button
            .onChange(of: selectedNoteID) { oldID, newID in
                // Clean up the PREVIOUS note if it was left empty AND we're switching to another note
                // Don't auto-delete when just clearing the selection (e.g. switching to attachments)
                if let oldID, let _ = newID, oldID != newID {
                    autoDeleteEmptyNote(oldID)
                }
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

            unifiedRecordsList
                .frame(maxHeight: .infinity)
        }
        .padding(.top, 4)
        .background(Color.systemGroupedBg)
    }

    private var topActionButtons: some View {
        HStack(spacing: isCompact ? 8 : 14) {
            recordActionBtn(title: "Add Note", icon: "doc.badge.plus", color: .blue) { showNewNoteSheet = true }
            recordActionBtn(title: "Add Vitals", icon: "waveform.path.ecg", color: .green) { openNewVitalsEntry() }
            attachmentMenuButton
        }
        .padding(.horizontal, 12)
    }

    /// Attachment button styled to match Add Note / Add Vitals.
    private var attachmentMenuButton: some View {
        Menu {
            Menu("Import Files") {
                Button("Medical Report") { pendingAttachmentCategory = .medicalReport; attachmentSourceIsPhotos = false; openPicker() }
                Button("Radiology") { pendingAttachmentCategory = .radiology; attachmentSourceIsPhotos = false; openPicker() }
                Button("Laboratory") { pendingAttachmentCategory = .laboratory; attachmentSourceIsPhotos = false; openPicker() }
                Button("Special Tests (EEG etc.)") { pendingAttachmentCategory = .eeg; attachmentSourceIsPhotos = false; openPicker() }
                Button("Other") { pendingAttachmentCategory = .other; attachmentSourceIsPhotos = false; openPicker() }
            }
            Menu("Import Photos") {
                Button("Medical Report") { pendingAttachmentCategory = .medicalReport; attachmentSourceIsPhotos = true; openPicker() }
                Button("Radiology") { pendingAttachmentCategory = .radiology; attachmentSourceIsPhotos = true; openPicker() }
                Button("Laboratory") { pendingAttachmentCategory = .laboratory; attachmentSourceIsPhotos = true; openPicker() }
                Button("Special Tests (EEG etc.)") { pendingAttachmentCategory = .eeg; attachmentSourceIsPhotos = true; openPicker() }
                Button("Other") { pendingAttachmentCategory = .other; attachmentSourceIsPhotos = true; openPicker() }
            }
        } label: {
            VStack(spacing: isCompact ? 4 : 8) {
                Image(systemName: "paperclip").font(.system(size: isCompact ? 18 : 26, weight: .semibold))
                Text("Attach").font(isCompact ? .caption2 : .footnote).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: isCompact ? 44 : 76)
            .background(Color.orange.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 10 : 14))
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
    }

    private func recordActionBtn(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: isCompact ? 4 : 8) {
                Image(systemName: icon).font(.system(size: isCompact ? 18 : 26, weight: .semibold))
                Text(title).font(isCompact ? .caption2 : .footnote).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 44 : 76)
            .background(color.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 10 : 14))
        }
        .buttonStyle(.plain)
    }

    private var unifiedRecordsList: some View {
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

            Section("Notes") {
                ForEach(filteredNotes) { note in
                    Button { selectNote(note.id) } label: { NoteRow(note: note) }
                }
            }

            Section("Attachments") {
                if filteredAttachments.isEmpty {
                    Text("No attachments")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredAttachments) { att in
                        Button {
                            selectedAttachmentID = att.id
                            selectedNoteID = nil
                        } label: {
                            AttachmentRow(attachment: att)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
            .inlineNavigationTitle()
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 350, minHeight: 400)
        #endif
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
        }
    }

    private func hasUnsavedChanges(_ noteID: UUID) -> Bool {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return false }
        let currentBody = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !currentBody.isEmpty && currentBody != note.type.defaultBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoDeleteEmptyNote(_ noteID: UUID) {
        guard let note = store.notes.first(where: { $0.id == noteID }) else { return }
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultBody = note.type.defaultBody.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only auto-delete if body is completely empty OR still just the untouched template
        if body.isEmpty || body == defaultBody {
            store.deleteNote(noteID)
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
    }

    private func openPicker() {
        if attachmentSourceIsPhotos {
            showPhotoPicker = true
        } else {
            showFileImporter = true
        }
    }

    /// Persistent directory for attachment files — iCloud-aware.
    private var attachmentsDir: URL {
        iCloudSyncManager.shared.directoryURL(for: "AttachmentFiles")
    }

    private func handleAttachmentImport(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            for url in urls {
                // Access security-scoped resource and copy into app sandbox
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let destName = "\(UUID().uuidString)_\(url.lastPathComponent)"
                let destURL = attachmentsDir.appendingPathComponent(destName)
                do {
                    try FileManager.default.copyItem(at: url, to: destURL)
                } catch {
                    print("Failed to copy attachment: \(error)")
                    continue
                }

                var att = Attachment(patientID: patient.id, type: pendingAttachmentCategory)
                att.filename = url.lastPathComponent
                att.fileURL = destURL
                store.addAttachment(att)
            }
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
                        let destName = "\(UUID().uuidString)_\(filename)"
                        let destURL = attachmentsDir.appendingPathComponent(destName)
                        try? data.write(to: destURL)

                        var att = Attachment(patientID: patient.id, type: pendingAttachmentCategory)
                        att.filename = filename
                        att.fileURL = destURL
                        store.addAttachment(att)
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

    @State private var showPreview = false
    @State private var showDeleteConfirm = false
    @State private var showAIAnalysis = false
    @Environment(\.horizontalSizeClass) private var hSize

    /// Computed every render — no stale @State issues.
    private var fileOnDisk: URL? { attachment.resolvedFileURL }

    private var shouldShowInline: Bool {
        #if os(macOS)
        return fileOnDisk != nil   // always show inline on Mac
        #else
        return showPreview && fileOnDisk != nil
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with filename and action buttons
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: attachment.type.iconName)
                        .font(.title2)
                        .foregroundStyle(attachment.type.displayColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                            .font(.headline)
                        Text(attachment.type.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    attachmentActionButtons
                }
            }
            .padding()

            Divider()

            // Inline preview area
            if shouldShowInline, let url = fileOnDisk {
                QuickLookPreview(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(url)  // force SwiftUI to recreate view when URL changes
            } else if fileOnDisk == nil {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.red.opacity(0.6))
                    Text("File not found on disk")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    if let stored = attachment.fileURL {
                        Text(stored.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: attachment.type.iconName)
                        .font(.system(size: 64))
                        .foregroundStyle(attachment.type.displayColor.opacity(0.4))
                    Text("Tap Preview to view this file")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAIAnalysis) {
            AttachmentAISheet(attachment: attachment)
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
        #if os(iOS)
        Button {
            showPreview = true
        } label: {
            Label("Preview", systemImage: "eye")
        }
        .buttonStyle(.borderedProminent)
        #endif

        Button {
            showAIAnalysis = true
        } label: {
            Label("AI Analyze", systemImage: "brain.head.profile")
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)

        Button {
            shareAttachment()
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)

        Button {
            printAttachment()
        } label: {
            Label("Print", systemImage: "printer")
        }
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
    }

    private func shareAttachment() {
        guard let url = fileOnDisk else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SharePrintPresenter.share(items: [url])
        }
    }

    private func printAttachment() {
        guard let url = fileOnDisk else { return }
        SharePrintPresenter.printURL(url, jobName: attachment.filename)
    }
}

// MARK: - Attachment AI Analysis Sheet

private struct AttachmentAISheet: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    enum AIModel: String, CaseIterable {
        case claude = "Claude"
        case gpt = "GPT-4o"
        case eegServer = "EEG Server"
    }

    @State private var selectedModel: AIModel = .claude
    @State private var eegServerURL: String = EEGServerConfig.baseURL

    /// Models available for this attachment type
    private var availableModels: [AIModel] {
        if attachment.type == .eeg {
            return AIModel.allCases
        } else {
            return [.claude, .gpt]
        }
    }
    @State private var prompt: String = ""
    @State private var result: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Model picker
                HStack(spacing: 8) {
                    Text("Model:").font(.caption).foregroundStyle(.secondary)
                    Picker("Model", selection: $selectedModel) {
                        Text("Claude").tag(AIModel.claude)
                        Text("GPT-4o").tag(AIModel.gpt)
                        if attachment.type == .eeg {
                            Text("EEG Server").tag(AIModel.eegServer)
                        }
                    }
                    .pickerStyle(.segmented)
                    .id(attachment.type)
                }
                .padding(.horizontal)
                .padding(.top)

                Divider().padding(.top, 8)

                // EEG Server URL (only when EEG Server selected)
                if selectedModel == .eegServer {
                    HStack(spacing: 8) {
                        Text("Server:").font(.caption).foregroundStyle(.secondary)
                        TextField("http://localhost:5050", text: $eegServerURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onChange(of: eegServerURL) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "EEG_SERVER_URL")
                            }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Attachment info
                        HStack(spacing: 12) {
                            Image(systemName: attachment.type.iconName)
                                .font(.title2)
                                .foregroundStyle(attachment.type.displayColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.filename.isEmpty ? "Attachment" : attachment.filename)
                                    .font(.subheadline).bold()
                                Text(attachment.type.rawValue)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.secondarySystemGroupedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Prompt
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prompt").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $prompt)
                                .frame(minHeight: 60, maxHeight: 120)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                        }

                        // Send button
                        Button {
                            Task { await analyze() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: selectedModel == .eegServer ? "waveform.path.ecg" : (selectedModel == .claude ? "brain.head.profile" : "brain"))
                                }
                                Text(isLoading ? "Analyzing..." : "Analyze with \(selectedModel.rawValue)")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isLoading || prompt.trimmingCharacters(in: .whitespaces).isEmpty)

                        // Error
                        if !errorMessage.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                Text(errorMessage).font(.caption).foregroundStyle(.red)
                            }
                        }

                        // Result
                        if !result.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("AI Analysis").font(.headline)
                                    Spacer()
                                    Button {
                                        PlatformPasteboard.copy(result)
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc").font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                                }

                                Text(result)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color.secondarySystemGroupedBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                // Disclaimer
                                Text("This AI analysis is for informational purposes only and should not replace clinical judgment.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Analyze")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                prompt = defaultPrompt(for: attachment.type)
                if attachment.type == .eeg {
                    selectedModel = .eegServer
                }
            }
        }
    }

    private func defaultPrompt(for type: AttachmentType) -> String {
        switch type {
        case .eeg:
            return "Analyze this EEG recording. Describe the background activity, any focal or generalized abnormalities, and provide an interpretation."
        case .radiology:
            return "Analyze this radiological image. Describe the findings and provide an impression."
        case .laboratory:
            return "Analyze these laboratory results. Identify any abnormal values and provide clinical significance."
        case .medicalReport:
            return "Analyze this medical document and summarize the key findings."
        case .other:
            return "Analyze this medical document and summarize the key findings."
        }
    }

    private func analyze() async {
        isLoading = true
        errorMessage = ""

        guard let fileURL = attachment.resolvedFileURL else {
            errorMessage = "No file URL available for this attachment."
            isLoading = false
            return
        }

        do {
            let response: String

            if selectedModel == .eegServer {
                // Send raw EEG file to local MNE-Python server
                response = try await EEGAnalysisService().analyze(
                    fileURL: fileURL,
                    prompt: prompt
                )
            } else {
                // Vision-based analysis (Claude / GPT)
                let images = try loadImages(from: fileURL)
                guard !images.isEmpty else {
                    errorMessage = "Could not read image data from file."
                    isLoading = false
                    return
                }

                let system = """
                You are an expert medical imaging and document analyst. Provide a thorough, \
                structured analysis. Use appropriate medical terminology. Always note that this \
                is an AI-assisted analysis and should be confirmed by a qualified specialist.
                """

                switch selectedModel {
                case .claude:
                    response = try await ClaudeService.shared.generateWithImages(
                        system: system,
                        userMessage: prompt,
                        images: images,
                        maxTokens: 4096
                    )
                case .gpt:
                    response = try await OpenAIService.shared.generateWithImages(
                        instructions: system,
                        input: prompt,
                        images: images,
                        maxOutputTokens: 4096
                    )
                case .eegServer:
                    response = "" // Already handled above
                }
            }

            await MainActor.run { result = response }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isLoading = false }
    }

    private func loadImages(from url: URL) throws -> [(data: Data, mediaType: String)] {
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            return try renderPDFPages(url: url)
        } else {
            let data = try Data(contentsOf: url)
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp"]
            guard imageExtensions.contains(ext) else {
                throw NSError(domain: "Attachment", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "This file type (.\(ext)) cannot be analyzed visually. AI analysis requires an image or PDF."
                ])
            }
            let mediaType: String
            switch ext {
            case "png": mediaType = "image/png"
            case "gif": mediaType = "image/gif"
            case "webp": mediaType = "image/webp"
            default: mediaType = "image/jpeg"
            }
            return [(data: data, mediaType: mediaType)]
        }
    }

    private func renderPDFPages(url: URL) throws -> [(data: Data, mediaType: String)] {
        guard let doc = PDFDocument(url: url) else {
            throw NSError(domain: "PDF", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Could not open PDF document."
            ])
        }

        var images: [(data: Data, mediaType: String)] = []
        let maxPages = min(doc.pageCount, 5)

        for i in 0..<maxPages {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 1.5
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

            #if os(iOS)
            let renderer = UIGraphicsImageRenderer(size: size)
            let imageData = renderer.jpegData(withCompressionQuality: 0.6) { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            images.append((data: imageData, mediaType: "image/jpeg"))
            #else
            let nsImage = NSImage(size: size)
            nsImage.lockFocus()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: ctx)
            }
            nsImage.unlockFocus()
            if let tiff = nsImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) {
                images.append((data: jpeg, mediaType: "image/jpeg"))
            }
            #endif
        }
        return images
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
