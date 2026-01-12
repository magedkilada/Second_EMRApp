//
//  RecordsWorkspaceView.swift
//  Second_EMRApp
//“BaselineContract

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import QuickLook
import PhotosUI
import UIKit

/// Master-detail workspace for a single patient's medical records.
/// - Left: templates + notes + vitals + attachments
/// - Right: selected note editor OR attachment preview
struct RecordsWorkspaceView: View {

    // MARK: - Inputs
    let patient: Patient

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - UI State
    @State private var recordSearch: String = ""

    // Templates
    @State private var showTemplates: Bool = false
    @State private var pendingTemplateType: RecordNoteType? = nil
    @State private var showTemplateDecision: Bool = false
    @State private var showBatchPrint = false

    // Vitals
    @State private var showVitalsSheet: Bool = false
    @State private var editingVitals: VitalsEntry? = nil

    // Attachment import
    @State private var pendingImportCategory: Attachment.Category = .medicalReport
    @State private var showFileImporter: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil

    // Auto-save handshake with NoteEditorView
    @State private var autoSaveToken: UUID = UUID()
    @State private var pendingTemplateAction: PendingTemplateAction? = nil

    // iPhone navigation
    @State private var pushDetail: Bool = false

    private enum PendingTemplateAction {
        case saveAndStart(RecordNoteType)
        case deleteAndStart(RecordNoteType)
    }

    // MARK: - Derived data
    private var q: String { recordSearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var patientNotes: [RecordNote] {
        let base = store.notes
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }

        guard !q.isEmpty else { return base }
        let qq = norm(q)
        return base.filter { n in
            norm(n.type.rawValue).contains(qq) || norm(n.body).contains(qq)
        }
    }

    private var patientVitals: [VitalsEntry] {
        let base = store.vitals(for: patient.id)
        guard !q.isEmpty else { return base }
        let qq = norm(q)
        return base.filter { v in
            norm(vitalsSummaryLine(v)).contains(qq) ||
            norm(v.measuredAt.formatted(date: .abbreviated, time: .shortened)).contains(qq)
        }
    }

    private var patientAttachments: [Attachment] {
        let base = store.attachments
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted { $0.importedAt > $1.importedAt }

        guard !q.isEmpty else { return base }
        let qq = norm(q)
        return base.filter { a in
            norm(a.originalFileName).contains(qq) ||
            norm(a.storedFileName).contains(qq) ||
            norm(a.category.rawValue).contains(qq)
        }
    }

    // MARK: - Body
    var body: some View {
        Group {
            if isPhone {
                NavigationStack {
                    leftPane
                        .navigationTitle("Medical Records")
                        .navigationBarTitleDisplayMode(.inline)
                        .background(
                            NavigationLink("", destination: rightPane, isActive: $pushDetail)
                                .hidden()
                        )
                }
            } else {
                HStack(spacing: 0) {
                    leftPane
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
                        .background(.background)

                    Divider()

                    rightPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                }
            }
        }
        // Clear selections when switching patients (prevents “old note shows under new patient”)
        .onChange(of: patient.id) { _, _ in
            recordSearch = ""
            store.selectedNoteID = nil
            store.selectedAttachmentID = nil
            store.selectedVitalID = nil
            pushDetail = false
        }
        // Vitals sheet
        .sheet(isPresented: $showVitalsSheet) {
            VitalsEntrySheet(
                patientID: patient.id,
                existing: editingVitals,
                onSave: { saved in
                    store.updateVital(saved)
                    showVitalsSheet = false
                    editingVitals = nil
                },
                onCancel: {
                    showVitalsSheet = false
                    editingVitals = nil
                }
            )
        }
        // Template decision box
        .alert("Template", isPresented: $showTemplateDecision) {
            Button("Save current note & start new note") {
                guard let t = pendingTemplateType else { return }
                pendingTemplateAction = .saveAndStart(t)
                autoSaveToken = UUID() // triggers NoteEditorView auto-save
            }
            Button("Replace (delete current) & start new note", role: .destructive) {
                guard let t = pendingTemplateType else { return }
                pendingTemplateAction = .deleteAndStart(t)
                autoSaveToken = UUID() // triggers NoteEditorView auto-save (then we delete)
            }
            Button("Cancel", role: .cancel) {
                pendingTemplateType = nil
            }
        } message: {
            Text("Choose whether to keep the current note (save it first if needed) or delete it, then start a new note from the template.")
        }
        // File importer attached to ROOT
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importAttachment(from: url, category: pendingImportCategory)
            case .failure(let err):
                store.lastErrorMessage = "Import failed: \(err.localizedDescription)"
            }
        }
        // Photos picker
        .sheet(isPresented: $showPhotoPicker) {
            NavigationStack {
                VStack(spacing: 16) {
                    Text("Choose a photo").font(.headline)

                    PhotosPicker(
                        selection: $pickedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Pick from Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Imported photo will be saved under: \(pendingImportCategory.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding()
                .navigationTitle("Import Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            pickedPhotoItem = nil
                            showPhotoPicker = false
                        }
                    }
                }
            }
        }
        // Photo result
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                await importPickedPhoto(item, category: pendingImportCategory)
                await MainActor.run {
                    pickedPhotoItem = nil
                    showPhotoPicker = false
                }
            }
        }
    }

    // MARK: - Left pane
    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                TextField("Search notes, vitals & attachments", text: $recordSearch)
                    .textFieldStyle(.roundedBorder)

                // Templates
                GroupBox {
                    DisclosureGroup("Templates", isExpanded: $showTemplates) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(RecordNoteType.allCases) { t in
                                Button {
                                    handleTemplateTapped(t)
                                } label: {
                                    HStack {
                                        Text(t.rawValue)
                                        Spacer()
                                        Image(systemName: "doc.on.doc")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if t != RecordNoteType.allCases.last {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                // Notes
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Notes").font(.headline)
                            Spacer()
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
                                        if isPhone { pushDetail = true }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(n.type.rawValue)
                                                .font(.headline)
                                            Text(n.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Smart Vitals
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Smart Vitals").font(.headline)
                            Spacer()
                            Button {
                                editingVitals = nil
                                showVitalsSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        if patientVitals.isEmpty {
                            Text("No vitals yet")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(patientVitals) { v in
                                    Button {
                                        editingVitals = v
                                        showVitalsSheet = true
                                        if isPhone { pushDetail = false }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(v.measuredAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.headline)
                                                Spacer()
                                                if let bmi = v.bmi {
                                                    Text(String(format: "BMI %.1f", bmi))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Text(vitalsSummaryLine(v))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Attachments
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Attachments").font(.headline)
                            Spacer()
                            Menu {
                                attachmentsImportMenu
                            } label: {
                                Image(systemName: "paperclip")
                            }
                            .buttonStyle(.bordered)
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
                                        if isPhone { pushDetail = true }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "paperclip")
                                                .foregroundStyle(.secondary)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(a.originalFileName.isEmpty ? a.storedFileName : a.originalFileName)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Text(a.category.rawValue)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Text(a.importedAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    // MARK: - Right pane
    private var rightPane: some View {
        Group {
            // NOTE (must belong to THIS patient)
            if let nid = store.selectedNoteID,
               let n = store.notes.first(where: { $0.id == nid && !$0.isDeleted && $0.patientID == patient.id }) {

                NoteEditorView(
                    patient: patient,
                    noteID: n.id,
                    autoSaveRequestToken: autoSaveToken,
                    onAutoSaveCompleted: {
                        continuePendingTemplateAction()
                    },
                    onRequestImportAttachment: { source, category in
                        pendingImportCategory = category
                        switch source {
                        case .files:  showFileImporter = true
                        case .photos: showPhotoPicker = true
                        }
                    }
                )
                .environmentObject(store)

            // ATTACHMENT (must belong to THIS patient)
            } else if let aid = store.selectedAttachmentID,
                      let a = store.attachments.first(where: { $0.id == aid && !$0.isDeleted && $0.patientID == patient.id }) {

                AttachmentPreviewPane(
                    patient: patient,
                    attachment: a,
                    fileURL: store.attachmentFileURL(a)
                )

            } else {
                ContentUnavailableView("Select a note, vitals, or attachment", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Templates behavior
    private func handleTemplateTapped(_ t: RecordNoteType) {
        pendingTemplateType = t

        // If no note selected -> create immediately
        guard let nid = store.selectedNoteID,
              let selected = store.note(by: nid) else {
            createAndSelectNewNote(type: t)
            pendingTemplateType = nil
            return
        }

        // If finalized -> cannot replace/delete; create new immediately
        if selected.isFinalized {
            createAndSelectNewNote(type: t)
            pendingTemplateType = nil
            return
        }

        // Otherwise show decision alert
        showTemplateDecision = true
    }

    private func continuePendingTemplateAction() {
        guard let action = pendingTemplateAction else { return }
        pendingTemplateAction = nil
        showTemplateDecision = false

        switch action {
        case .saveAndStart(let t):
            // autosave already happened inside NoteEditorView
            createAndSelectNewNote(type: t)

        case .deleteAndStart(let t):
            if let nid = store.selectedNoteID {
                if let selected = store.note(by: nid), selected.isFinalized {
                    store.lastErrorMessage = "This note is finalized and cannot be deleted."
                } else {
                    store.deleteNote(nid)
                }
            }
            createAndSelectNewNote(type: t)
        }

        pendingTemplateType = nil
    }

    private func createAndSelectNewNote(type: RecordNoteType) {
        let note = store.addNote(patientID: patient.id, type: type)
        store.selectedNoteID = note.id
        store.selectedAttachmentID = nil
        store.selectedVitalID = nil
        if isPhone { pushDetail = true }
    }

    // MARK: - Attachments import menu
    private var attachmentsImportMenu: some View {
        Group {
            Menu("Files…") {
                ForEach(Attachment.Category.allCases) { cat in
                    Button(cat.rawValue) {
                        pendingImportCategory = cat
                        showFileImporter = true
                    }
                }
            }
            Menu("Photos…") {
                ForEach(Attachment.Category.allCases) { cat in
                    Button(cat.rawValue) {
                        pendingImportCategory = cat
                        showPhotoPicker = true
                    }
                }
            }
        }
    }

    // MARK: - Import helpers
    private func importAttachment(from url: URL, category: Attachment.Category) {
        do {
            let fm = FileManager.default
            let destDir = store.attachmentsDirectory(for: patient.id)

            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            let storedName = "\(UUID().uuidString).\(ext)"
            let destURL = destDir.appendingPathComponent(storedName)

            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)

            var a = Attachment(
                patientID: patient.id,
                category: category,
                originalFileName: url.lastPathComponent,
                storedFileName: storedName
            )
            a.importedAt = Date()
            a.isDeleted = false

            store.attachments.insert(a, at: 0)
            store.saveAttachments()

            store.selectedAttachmentID = a.id
            store.selectedNoteID = nil
            store.selectedVitalID = nil
            if isPhone { pushDetail = true }

        } catch {
            store.lastErrorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func importPickedPhoto(_ item: PhotosPickerItem, category: Attachment.Category) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            let destDir = store.attachmentsDirectory(for: patient.id)
            let storedName = "\(UUID().uuidString).jpg"
            let destURL = destDir.appendingPathComponent(storedName)
            try data.write(to: destURL, options: [.atomic])

            var a = Attachment(
                patientID: patient.id,
                category: category,
                originalFileName: "Photo.jpg",
                storedFileName: storedName
            )
            a.importedAt = Date()
            a.isDeleted = false

            await MainActor.run {
                store.attachments.insert(a, at: 0)
                store.saveAttachments()

                store.selectedAttachmentID = a.id
                store.selectedNoteID = nil
                store.selectedVitalID = nil
                if isPhone { pushDetail = true }
            }
        } catch {
            await MainActor.run {
                store.lastErrorMessage = "Photo import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Vitals formatting
    private func vitalsSummaryLine(_ v: VitalsEntry) -> String {
        var parts: [String] = []
        if let s = v.systolicBP, let d = v.diastolicBP { parts.append("BP \(s)/\(d)") }
        if let hr = v.heartRate { parts.append("HR \(hr)") }
        if let o2 = v.spo2 { parts.append("SpO₂ \(o2)%") }
        if let t = v.tempC { parts.append(String(format: "T %.1f°C", t)) }
        if let w = v.weightKg { parts.append(String(format: "Wt %.1f kg", w)) }
        if let h = v.heightCm { parts.append(String(format: "Ht %.0f cm", h)) }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Attachment Preview Pane (Quick Look + Share/Print)
private struct AttachmentPreviewPane: View {
    let patient: Patient
    let attachment: Attachment
    let fileURL: URL

    @State private var showShare = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.originalFileName.isEmpty ? attachment.storedFileName : attachment.originalFileName)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)

                    Text(attachment.category.rawValue)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                Spacer()

                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button {
                    EMRPrintHelper.printFile(fileURL, jobName: attachment.originalFileName.isEmpty ? "Attachment" : attachment.originalFileName)
                } label: {
                    Image(systemName: "printer")
                }
                .buttonStyle(.bordered)
            }

            Divider()

            if FileManager.default.fileExists(atPath: fileURL.path) {
                QuickLookPreview(url: fileURL)
            } else {
                ContentUnavailableView("File not found", systemImage: "exclamationmark.triangle")
            }
        }
        .padding()
        .sheet(isPresented: $showShare) {
            EMRShareSheetView(items: [fileURL])
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Vitals Entry Sheet
private struct VitalsEntrySheet: View {
    let patientID: UUID
    let existing: VitalsEntry?
    let onSave: (VitalsEntry) -> Void
    let onCancel: () -> Void

    @State private var measuredAt: Date = Date()

    @State private var sbp: String = ""
    @State private var dbp: String = ""
    @State private var hr: String = ""
    @State private var spo2: String = ""
    @State private var tempC: String = ""

    @State private var weightKg: String = ""
    @State private var heightCm: String = ""
    @State private var headCirc: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Measured") {
                    DatePicker("Date/Time", selection: $measuredAt)
                }

                Section("Vitals") {
                    TextField("SBP", text: $sbp).keyboardType(.numberPad)
                    TextField("DBP", text: $dbp).keyboardType(.numberPad)
                    TextField("HR", text: $hr).keyboardType(.numberPad)
                    TextField("SpO₂", text: $spo2).keyboardType(.numberPad)
                    TextField("Temp (°C)", text: $tempC).keyboardType(.decimalPad)
                }

                Section("Anthropometrics") {
                    TextField("Weight (kg)", text: $weightKg).keyboardType(.decimalPad)
                    TextField("Height (cm)", text: $heightCm).keyboardType(.decimalPad)
                    TextField("Head circumference (cm)", text: $headCirc).keyboardType(.decimalPad)
                }
            }
            .navigationTitle(existing == nil ? "New Vitals" : "Edit Vitals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var v = existing ?? VitalsEntry(patientID: patientID)
                        v.patientID = patientID
                        v.measuredAt = measuredAt

                        v.systolicBP = Int(sbp)
                        v.diastolicBP = Int(dbp)
                        v.heartRate = Int(hr)
                        v.spo2 = Int(spo2)
                        v.tempC = Double(tempC)

                        v.weightKg = Double(weightKg)
                        v.heightCm = Double(heightCm)
                        v.headCircumferenceCm = Double(headCirc)

                        onSave(v)
                    }
                }
            }
            .onAppear {
                if let e = existing {
                    measuredAt = e.measuredAt
                    sbp = e.systolicBP.map(String.init) ?? ""
                    dbp = e.diastolicBP.map(String.init) ?? ""
                    hr = e.heartRate.map(String.init) ?? ""
                    spo2 = e.spo2.map(String.init) ?? ""
                    tempC = e.tempC.map { String($0) } ?? ""
                    weightKg = e.weightKg.map { String($0) } ?? ""
                    heightCm = e.heightCm.map { String($0) } ?? ""
                    headCirc = e.headCircumferenceCm.map { String($0) } ?? ""
                }
            }
        }
    }
}
