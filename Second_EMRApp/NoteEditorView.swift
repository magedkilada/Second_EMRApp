import SwiftUI
import UIKit

struct NoteEditorView: View {

    // MARK: - Inputs
    let patient: Patient
    let noteID: UUID

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - Local state
    @State private var note: RecordNote? = nil
    @State private var editorText: String = ""
    @State private var isDirty: Bool = false

    // Save UX
    @State private var showSavedToast: Bool = false

    // Confirmations
    @State private var showConfirmDelete: Bool = false
    @State private var showConfirmFinalize: Bool = false

    // Template replacement confirm
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

    private var headerPhysicianLine: String { store.treatingPhysicianName }
    private var headerClinic: String { store.clinicName }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 10) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(patientDisplayName)
                        .font(.largeTitle).bold()

                    Spacer()

                    if note?.isFinalized == true {
                        Text("FINALIZED")
                            .font(.caption).bold()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                    }
                }

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
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
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

        // Finalize confirm (irreversible)
        .alert("Finalize this note?", isPresented: $showConfirmFinalize) {
            Button("Cancel", role: .cancel) { }
            Button("Finalize", role: .destructive) { finalizeNow() }
        } message: {
            Text("Finalized notes cannot be edited.")
        }

        // Template replace confirm
        .alert("Replace current note with template?", isPresented: $showReplaceTemplateConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Replace", role: .destructive) {
                // ✅ user request: auto-save current before replacing (unless deleted)
                saveSilentlyIfDirty()
                editorText = pendingTemplateText
                markDirtyAndAutosave()      // will save new text shortly
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

    // MARK: - Top toolbar (✅ remove Template, keep AI/Translate only)
    @ToolbarContentBuilder
    private var topRightToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Menu("AI") {
                    Button("Improve note (replace)") { /* wire later */ }
                    Button("Improve note (copy)") { /* wire later */ }
                    Button("Ask about note") { /* wire later */ }
                    Button("Clear AI") { /* wire later */ }
                }

                Menu("Translate") {
                    Button("Arabic") { /* wire later */ }
                    Button("English") { /* wire later */ }
                    Button("French") { /* wire later */ }
                    Button("German") { /* wire later */ }
                    Button("Clear translation") { /* wire later */ }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Bottom bar (✅ add Finalize + move Batch Print to printer menu)
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

            // ✅ Finalize button (bottom bar)
            Button {
                showConfirmFinalize = true
            } label: {
                Label("Finalize", systemImage: "checkmark.seal")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
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

            // ✅ Printer is now a menu: Print this + Batch Print
            Menu {
                Button("Print This Note", systemImage: "printer") {
                    printNow()
                }
                Button("Batch Print…", systemImage: "tray.full") {
                    showBatchPrintSheet = true
                }
            } label: {
                Image(systemName: "printer")
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Public API called by the LEFT templates list (use this from RecordsWorkspaceView)
    func requestReplaceWithTemplate(_ type: RecordNoteType) {
        pendingTemplateText = store.templateText(for: type)
        showReplaceTemplateConfirm = true
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

            // ✅ iPad workflow: clear editor after save
            if !isPhone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    store.selectedNoteID = nil
                }
            }
        }
    }

    // MARK: - Finalize
    private func finalizeNow() {
        saveSilentlyIfDirty()
        guard var n = note else { return }
        n.isFinalized = true
        n.updatedAt = Date()
        store.updateNote(n)
        note = n
    }

    // MARK: - Delete
    private func deleteNow() {
        store.deleteNote(id: noteID)

        if isPhone {
            dismiss()
        } else {
            store.selectedNoteID = nil
        }
    }
    // MARK: - Share / Print
    private func shareNow() {
        saveSilentlyIfDirty()
        shareItems = ["Medical Record", editorText]
        showShareSheet = true
    }

    private func printNow() {
        saveSilentlyIfDirty()
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
