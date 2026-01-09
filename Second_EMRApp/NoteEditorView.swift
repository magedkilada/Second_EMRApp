import SwiftUI
import UIKit

struct NoteEditorView: View {

    // MARK: - Inputs
    let patient: Patient
    let noteID: UUID

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state
    @State private var note: RecordNote? = nil
    @State private var editorText: String = ""
    @State private var isDirty: Bool = false

    // Save UX
    @State private var showSavedToast: Bool = false

    // Confirmations
    @State private var showConfirmDelete: Bool = false
    @State private var showReplaceTemplateConfirm: Bool = false
    @State private var pendingTemplateText: String = ""

    // Share / Print
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    // Batch print
    @State private var showBatchPrintSheet: Bool = false

    // Debounced autosave
    @State private var autosaveWorkItem: DispatchWorkItem? = nil

    // MARK: - Derived
    private var canEdit: Bool { !(note?.isFinalized ?? false) }

    private var patientDisplayName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Patient"
    }

    private var headerPhysicianLine: String {
        store.treatingPhysicianName
    }

    private var headerClinic: String {
        store.clinicName
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 10) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(patientDisplayName)
                    .font(.largeTitle).bold()

                Text(headerPhysicianLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(headerClinic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider().padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            // Editor
            TextEditor(text: $editorText)
                .font(.body)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .padding(.horizontal)
                .disabled(!canEdit)
                .onChange(of: editorText) { _, _ in
                    guard canEdit else { return }
                    markDirtyAndAutosave()
                }

            // Bottom action bar
            bottomBar
                .padding(.horizontal)
                .padding(.bottom, 10)
        }
        .navigationTitle(note?.type.rawValue ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topRightToolbar }
        .onAppear { loadNoteIfNeeded() }
        .onDisappear { saveSilentlyIfDirty() }

        // Share Sheet
        .sheet(isPresented: $showShareSheet) {
            NoteShareSheet(items: shareItems)
        }

        // Batch Print
        .sheet(isPresented: $showBatchPrintSheet) {
            BatchPrintView(patient: patient)
                .environmentObject(store)
        }

        // Delete confirm
        .alert("Delete note?", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteNow() }
        } message: {
            Text("This will permanently remove this note from this device.")
        }

        // Template replace confirm
        .alert("Replace current note with template?", isPresented: $showReplaceTemplateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Replace", role: .destructive) {
                editorText = pendingTemplateText
                markDirtyAndAutosave()
            }
        } message: {
            Text("This will overwrite the current note text.")
        }

        // Saved toast
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Text("Saved ✓")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 18)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSavedToast)
    }

    // MARK: - Top toolbar (AI / Translate placeholders + Template)
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {

            Menu {
                // Template menu
                Menu("Template") {
                    ForEach(RecordNoteType.allCases) { t in
                        Button(t.rawValue) {
                            pendingTemplateText = store.templateText(for: t)
                            showReplaceTemplateConfirm = true
                        }
                    }
                }

                // Placeholders for AI / Translate (wire later)
                // These buttons are intentionally safe stubs (no compile dependencies).
                Menu("AI") {
                    Button("Improve note (replace)") { /* wire to AI later */ }
                    Button("Improve note (copy)") { /* wire to AI later */ }
                    Button("Ask about note") { /* wire to AI later */ }
                    Button("Clear AI") { /* wire to AI later */ }
                }

                Menu("Translate") {
                    Button("Arabic") { /* wire to translate later */ }
                    Button("English") { /* wire to translate later */ }
                    Button("French") { /* wire to translate later */ }
                    Button("German") { /* wire to translate later */ }
                    Button("Clear translation") { /* wire to translate later */ }
                }

                Divider()

                Button("Batch Print…", systemImage: "tray.full") {
                    showBatchPrintSheet = true
                }

            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Bottom bar
    private var bottomBar: some View {
        HStack(spacing: 14) {

            Button {
                saveNow(showToast: true)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canEdit)

            Button(role: .destructive) {
                showConfirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)

            Button {
                shareNow()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)

            Button {
                printNow()
            } label: {
                Image(systemName: "printer")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Load
    private func loadNoteIfNeeded() {
        if let n = store.note(by: noteID) {
            note = n
            editorText = n.body
            isDirty = false
        } else {
            note = nil
            editorText = ""
        }
    }

    // MARK: - Dirty + autosave
    private func markDirtyAndAutosave() {
        isDirty = true

        autosaveWorkItem?.cancel()
        let work = DispatchWorkItem { saveSilentlyIfDirty() }
        autosaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func saveSilentlyIfDirty() {
        guard isDirty else { return }
        saveNow(showToast: false)
    }

    // MARK: - Save
    private func saveNow(showToast: Bool) {
        guard var n = note else { return }
        guard canEdit else { return }

        n.body = editorText
        n.updatedAt = Date()
        store.updateNote(n)

        note = n
        isDirty = false

        if showToast {
            showSavedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showSavedToast = false
            }
        }
    }

    // MARK: - Delete
    private func deleteNow() {
        store.deleteNote(id: noteID)
        dismiss()
    }

    // MARK: - Share / Print
    private func shareNow() {
        // Ensure latest text is saved silently before sharing
        saveSilentlyIfDirty()

        let text = editorText
        shareItems = ["Medical Record", text]
        showShareSheet = true
    }

    private func printNow() {
        saveSilentlyIfDirty()
        // If you have PrintShareHelper.swift in your project, keep this call.
        PrintShareHelper.printText(editorText, jobName: "Medical Record")
    }
}

// MARK: - Share Sheet (UIKit)

private struct NoteShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Batch Print (simple + stable)

private struct BatchPrintView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EMRStore

    let patient: Patient

    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText: String = ""

    private var filtered: [RecordNote] {
        let base = store.notes(for: patient.id)
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { n in
            n.type.rawValue.lowercased().contains(q) || n.body.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search notes…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                List(filtered, selection: $selectedIDs) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.type.rawValue).font(.headline)
                        Text(n.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Batch Print")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select All") { selectedIDs = Set(filtered.map { $0.id }) }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(role: .destructive) { selectedIDs.removeAll() } label: { Text("Clear") }
                    Spacer()
                    Button {
                        let picked = filtered.filter { selectedIDs.contains($0.id) }
                        let text = composedBatchText(picked)
                        PrintShareHelper.printText(text, jobName: "Batch Medical Record")
                        dismiss()
                    } label: {
                        Label("Print (\(selectedIDs.count))", systemImage: "printer.fill")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func composedBatchText(_ notes: [RecordNote]) -> String {
        var lines: [String] = []
        lines.append(patient.nameEnglish.isEmpty ? "Patient" : patient.nameEnglish)
        lines.append(String(repeating: "=", count: 36))
        lines.append("")

        for n in notes.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            lines.append(n.type.rawValue)
            lines.append(n.updatedAt.formatted(date: .abbreviated, time: .shortened))
            lines.append(String(repeating: "-", count: 36))
            lines.append(n.body)
            lines.append("")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
