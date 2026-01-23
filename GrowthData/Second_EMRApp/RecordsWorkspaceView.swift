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
    
    // MARK: - Unified selection (note / attachment / vitals list)
    private enum Selection: Hashable {
        case note(UUID)
        case attachment(UUID)
        case vitalsList
    }
    @State private var selection: Selection? = nil
    
    // MARK: - iPhone Navigation
    enum PhoneRoute: Hashable {
        case note(UUID)
        case attachment(UUID)
        case vitalsList
    }
    @State private var phonePath: [PhoneRoute] = []
    
    enum DetailSelection: Hashable {
        case note(UUID)
        case attachment(UUID)
        case vitalsList
    }


    
    // MARK: - Import UI
    @State private var importingCategory: Attachment.Category = .radiology
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    
    @State private var showConfirmDeleteVitals = false
    @State private var vitalsToDeleteID: UUID? = nil

    
    // MARK: - Toast
    @State private var showSavedToast = false
    
    // MARK: - Errors
    @State private var errorMessage: String?
    
    
    
    // MARK: - QuickLook
    @State private var previewItem: PreviewItem? = nil
    private struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    
    @State private var vitalsMode: VitalsMode = .list

    private enum VitalsMode: String, CaseIterable, Identifiable {
        case list = "List"
        case chart = "Chart"
        var id: String { rawValue }
    }
    
    
    // MARK: - Smart Vitals Sheet
    @State private var showSmartVitalsSheet = false
    @State private var pendingVitals = SmartVitalsEntry(patientID: UUID()) // overwritten on open
    
    // MARK: - Derived
    private var selectedNoteIsFinalized: Bool {
        guard let id = store.selectedNoteID,
              let n = noteByID(id) else { return false }
        return n.isFinalized
    }
    
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
    
    private var vitalsForPatient: [SmartVitalsEntry] {
        store.vitals
            .filter { $0.patientID == patient.id }
            .sorted { $0.recordedAt > $1.recordedAt }
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
        
        // Smart Vitals entry sheet
        .sheet(isPresented: $showSmartVitalsSheet) {
            SmartVitalsEntrySheet(
                patient: patient,
                vitals: $pendingVitals,
                onCancel: { showSmartVitalsSheet = false },
                onInsertIntoNote: { entry in
                    store.addOrUpdateVitals(entry)
                    insertVitalsIntoActiveNote(entry)
                    showSmartVitalsSheet = false
                },
                onSaveOnly: { entry in
                    store.addOrUpdateVitals(entry)
                    showSmartVitalsSheet = false
                }
            )
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
        
        // Preview sheet (QuickLook)
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        
        // Small toast (used when vitals are inserted/saved)
        .overlay(alignment: .topTrailing) {
            if showSavedToast {
                Text("Saved")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .padding()
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - iPhone layout
    private var phoneNavigationLayout: some View {
        NavigationStack(path: $phonePath) {
            recordsList
                .navigationTitle(patientName)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: PhoneRoute.self) { route in
                    switch route {
                    case .note(let id):
                        noteEditorDestination(noteID: id)
                            .environmentObject(physicians)
                        
                    case .attachment(let id):
                        attachmentDestination(attachmentID: id)
                        
                    case .vitalsList:
                        vitalsTableView
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
            switch selection {
                
            case .note(let id):
                noteEditorDestination(noteID: id)
                    .environmentObject(physicians)
                
            case .attachment(let id):
                attachmentDestination(attachmentID: id)
                
            case .vitalsList:
                vitalsTableView
                
            case nil:
                ContentUnavailableView("Select an item", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Left list (Notes / Vitals / Attachments)
    private var recordsList: some View {
        List {

            // NOTES section (includes Add Note + Smart Vitals entry)
            Section {
                Menu {
                    Button("H&P")          { addNote(type: RecordType.hp) }
                    Button("SOAP")         { addNote(type: RecordType.soap) }
                    Button("Operative")    { addNote(type: RecordType.operative) }
                    Button("Discharge")    { addNote(type: RecordType.discharge) }
                    Button("EEG")          { addNote(type: RecordType.eeg) }
                    Button("Prescription") { addNote(type: RecordType.prescription) }
                    Button("Clinical Note"){ addNote(type: RecordType.blank) }
                } label: {
                    Label("Add Note", systemImage: "square.and.pencil")
                        .font(.headline)
                }

                Button {
                    pendingVitals = SmartVitalsEntry(patientID: patient.id)
                    showSmartVitalsSheet = true
                } label: {
                    Label("Smart Vitals", systemImage: "waveform.path.ecg")
                        .font(.headline)
                }

                if notesForPatient.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notesForPatient) { note in
                        Button {
                            store.selectedNoteID = note.id
                            selection = .note(note.id)
                            if isPhone { phonePath.append(.note(note.id)) }
                        } label: {
                            noteRow(note)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            store.selectedNoteID == note.id
                            ? Color.yellow.opacity(0.25)
                            : Color.clear
                        )
                    }
                }
            } header: {
                Text("Notes")
            }

            // VITALS HISTORY (one line item -> opens table on right)
            Section("Vitals") {
                Button {
                    store.selectedNoteID = nil
                    selection = .vitalsList
                    if isPhone { phonePath.append(.vitalsList) }
                } label: {
                    HStack {
                        Label("Vitals History", systemImage: "waveform.path.ecg")
                        Spacer()
                        Text("\(vitalsForPatient.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    selection == .vitalsList
                    ? Color.yellow.opacity(0.18)
                    : Color.clear
                )
            }

            // ATTACHMENTS section
            Section("Attachments") {
                if attachmentsForPatient.isEmpty {
                    Text("No attachments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachmentsForPatient) { att in
                        Button {
                            store.selectedNoteID = nil
                            selection = .attachment(att.id)
                            if isPhone { phonePath.append(.attachment(att.id)) }
                        } label: {
                            attachmentRow(att)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selection == .attachment(att.id)
                            ? Color.yellow.opacity(0.18)
                            : Color.clear
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }


    // MARK: - Vitals (Table + Chart)

    private var vitalsTableView: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header row
            HStack(alignment: .center, spacing: 12) {
                Text("Vitals History")
                    .font(.title3).bold()

                Picker("Mode", selection: $vitalsMode) {
                    ForEach(VitalsMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260) // keeps it visible on iPad

                Spacer()

                if isPhone {
                    Button("Close") { selection = nil }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 4)

            // Content
            if vitalsForPatient.isEmpty {

                ContentUnavailableView("No vitals yet", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            } else {

                if vitalsMode == .chart {

                    // Placeholder for now (we’ll plug in VitalsChartView next)
                    VitalsChartView(vitals: vitalsForPatient, patientDOB: patient.dob)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                } else {

                    List {
                        ForEach(vitalsForPatient) { v in
                            HStack(alignment: .top, spacing: 12) {

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(v.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)

                                    Text(v.formattedBlock(includePercentiles: false, isUnder5: false))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Menu {
                                    Button {
                                        pendingVitals = v
                                        showSmartVitalsSheet = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        vitalsToDeleteID = v.id
                                        showConfirmDeleteVitals = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .alert("Delete vitals?", isPresented: $showConfirmDeleteVitals) {
                        Button("Delete", role: .destructive) {
                            if let id = vitalsToDeleteID {
                                store.deleteVitals(id)   // <-- keep YOUR store signature
                            }
                            vitalsToDeleteID = nil
                        }
                        Button("Cancel", role: .cancel) {
                            vitalsToDeleteID = nil
                        }
                    } message: {
                        Text("This cannot be undone.")
                    }
                }
            }
        }
        .padding()
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
    
    // MARK: - Insert vitals into active note (smart placement)
    private func insertVitalsIntoActiveNote(_ entry: SmartVitalsEntry) {
        
        guard let noteID = store.selectedNoteID,
              let idx = store.notes.firstIndex(where: { $0.id == noteID }) else {
            // No note selected; vitals still saved in vitals list.
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showSavedToast = false }
            return
        }
        
        let line = entry.formattedBlock(includePercentiles: false, isUnder5: false)
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        var text = store.notes[idx].body
        
        // 1) Prefer under PHYSICAL EXAMINATION
        if let insertIndex = insertionPoint(afterAnyOf: [
            "PHYSICAL EXAMINATION:",
            "PHYSICAL EXAM:",
            "PHYSICAL EXAMINATION",
            "PHYSICAL EXAM"
        ], in: text) {
            
            text = insertLine(line, into: text, at: insertIndex)
            
            // 2) Else under OBJECTIVE
        } else if let insertIndex = insertionPoint(afterAnyOf: [
            "OBJECTIVE:",
            "OBJECTIVE"
        ], in: text) {
            
            text = insertLine(line, into: text, at: insertIndex)
            
            // 3) Fallback: top of note
        } else {
            text = line + "\n" + text
        }
        
        store.notes[idx].body = text
        store.notes[idx].updatedAt = Date()
        store.lastModified = Date()
        
        store.saveNote(store.notes[idx]) // ✅ persistence + refresh
        
        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            showSavedToast = false
        }
    }
    
    private func insertionPoint(afterAnyOf markers: [String], in text: String) -> String.Index? {
        for m in markers {
            if let idx = insertionPoint(afterMarker: m, in: text) {
                return idx
            }
        }
        return nil
    }
    
    private func insertionPoint(afterMarker marker: String, in text: String) -> String.Index? {
        guard let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        if let lineEnd = text[range.upperBound...].firstIndex(of: "\n") {
            return text.index(after: lineEnd)
        } else {
            return range.upperBound
        }
    }
    
    private func insertLine(_ line: String, into text: String, at index: String.Index) -> String {
        var result = text
        
        if index > result.startIndex {
            let prev = result.index(before: index)
            if result[prev] != "\n" {
                result.insert("\n", at: index)
            }
        }
        
        result.insert(contentsOf: line + "\n", at: index)
        return result
    }
    
    // MARK: - Destinations
    private func noteEditorDestination(noteID: UUID) -> some View {
        Group {
            if let binding = bindingForNote(id: noteID) {
                NoteEditorView(note: binding, patient: patient) { saved in
                    var n = saved
                    n.updatedAt = Date()
                    binding.wrappedValue = n
                    store.lastModified = Date()
                    store.saveNote(n) // ✅ ensures persistence when Save is tapped
                }
                .onAppear {
                    store.selectedNoteID = noteID
                    selection = .note(noteID)
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
                    selection = .attachment(attachmentID)
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
            
            // Import menu
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
            
            // Delete current selection (note or attachment)
            Button(role: .destructive) {
                deleteCurrentSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(store.selectedNoteID == nil && !isAttachmentSelected)
        }
    }
    
    private var isAttachmentSelected: Bool {
        if case .attachment = selection { return true }
        return false
    }
    
    // MARK: - Data helpers
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
        selection = .note(n.id)
        
        store.saveNote(n) // optional, but makes it feel immediate
        
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
        
        store.saveNote(store.notes[idx])
    }
    
    private func deleteCurrentSelection() {
        if let id = store.selectedNoteID {
            store.notes.removeAll(where: { $0.id == id })
            store.selectedNoteID = nil
            selection = nil
            store.lastModified = Date()
            store.saveNotes()
        } else if case .attachment(let attID) = selection {
            store.attachments.removeAll(where: { $0.id == attID })
            selection = nil
            store.lastModified = Date()
            store.saveAttachments()
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
            let dest = try persistImportedData(
                data: data,
                fileName: filename,
                category: importingCategory
            )
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
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let preferred = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(att.patientID.uuidString, isDirectory: true)
            .appendingPathComponent(att.category.rawValue, isDirectory: true)
            .appendingPathComponent(att.storedFileName)
        
        if fm.fileExists(atPath: preferred.path) {
            return preferred
        }
        
        // Legacy fallbacks (safe)
        let fallbacks: [URL] = [
            docs.appendingPathComponent(att.storedFileName),
            docs.appendingPathComponent(att.patientID.uuidString)
                .appendingPathComponent(att.storedFileName),
            docs.appendingPathComponent("Attachments")
                .appendingPathComponent(att.storedFileName)
        ]
        
        return fallbacks.first { fm.fileExists(atPath: $0.path) }
    }
    
    private func persistImportedFile(
        url: URL,
        category: Attachment.Category
    ) throws -> URL {
        
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        let dir = docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(patient.id.uuidString, isDirectory: true)
            .appendingPathComponent(category.rawValue, isDirectory: true)
        
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let ext = url.pathExtension
        let stored = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        let dest = dir.appendingPathComponent(stored)
        
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: url, to: dest)
        return dest
    }
    
    private func persistImportedData(
        data: Data,
        fileName: String,
        category: Attachment.Category
    ) throws -> URL {
        
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
