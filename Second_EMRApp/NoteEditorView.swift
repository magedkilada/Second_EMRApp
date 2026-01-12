//
//  NoteEditorView.swift
//  Second_EMRApp
//

import SwiftUI
import UIKit

// Keep ONE definition in the whole project.
// If you already have ImportSource somewhere else, delete one of them.
enum ImportSource {
    case files
    case photos
}

struct NoteEditorView: View {

    // MARK: - Inputs
    let patient: Patient
    let noteID: UUID

    /// When this UUID changes, the editor MUST auto-save (if dirty),
    /// then call onAutoSaveCompleted so RecordsWorkspaceView can proceed.
    let autoSaveRequestToken: UUID

    let onAutoSaveCompleted: () -> Void

    /// Ask workspace to import attachment (keeps your existing pipeline unchanged)
    let onRequestImportAttachment: (ImportSource, Attachment.Category) -> Void

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore

    // MARK: - Local state
    @State private var note: RecordNote? = nil
    @State private var editorText: String = ""
    @State private var isDirty: Bool = false

    // UX
    @State private var showConfirmDelete: Bool = false
    @State private var showConfirmFinalize: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var showBatchPrint: Bool = false

    // Share sheet
    @State private var sharePayload: SharePayload? = nil

    // Focus
    @FocusState private var editorFocused: Bool

    // MARK: - Derived
    private var canEdit: Bool { !(note?.isFinalized ?? false) }

    private var titleText: String {
        note?.type.rawValue ?? "Note"
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {

            TextEditor(text: $editorText)
                .focused($editorFocused)
                .disabled(!canEdit)
                .padding()
                .onChange(of: editorText) { _, _ in
                    guard canEdit else { return }
                    isDirty = true
                }
                .onAppear {
                    loadNote()
                }
                .onChange(of: noteID) { _, _ in
                    loadNote()
                }

            Divider()

            bottomBar
                .padding()
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)

        // ✅ Auto-save trigger from RecordsWorkspaceView
        .onChange(of: autoSaveRequestToken) { _, _ in
            saveIfNeeded()
            onAutoSaveCompleted()
        }

        // Alerts
        .alert("Delete note?", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteNote()
            }
        } message: {
            Text("This will remove the note unless it is finalized.")
        }

        .alert("Finalize note?", isPresented: $showConfirmFinalize) {
            Button("Cancel", role: .cancel) {}
            Button("Finalize", role: .destructive) {
                finalizeNote()
            }
        } message: {
            Text("Finalized notes become read-only and cannot be deleted.")
        }

        // Share sheet (1 tap, iPad-safe)
        .sheet(item: $sharePayload) { payload in
            EMRShareSheetView(items: payload.items)
        }

        // Toast
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Text("Saved")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 60)
            }
        }
        .sheet(isPresented: $showBatchPrint) {
            BatchPrintView(patient: patient)
                .environmentObject(store)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {

            // Attachments
            Menu {
                ForEach(Attachment.Category.allCases) { cat in
                    Button("Files → \(cat.rawValue)") {
                        onRequestImportAttachment(.files, cat)
                    }
                    Button("Photos → \(cat.rawValue)") {
                        onRequestImportAttachment(.photos, cat)
                    }
                }
            } label: {
                Image(systemName: "paperclip")
            }

            Spacer()

            // Delete
            Button {
                showConfirmDelete = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(note?.isFinalized == true)

            // Share
            Button {
                saveIfNeeded()
                shareNote()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }

            // Print single
            Button {
                saveIfNeeded()
                printNote()
            } label: {
                Image(systemName: "printer")
            }

            // ✅ Batch Print (NEW)
            Button {
                saveIfNeeded()
                showBatchPrint = true
            } label: {
                Image(systemName: "printer.fill")
            }
            .help("Batch Print")

            // Finalize
            Button {
                showConfirmFinalize = true
            } label: {
                Label("Finalize", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(note?.isFinalized == true)
        }
    }
    // MARK: - Data
    private func loadNote() {
        guard let n = store.note(by: noteID) else {
            note = nil
            editorText = ""
            isDirty = false
            return
        }
        note = n
        editorText = n.body
        isDirty = false
    }

    private func saveIfNeeded() {
        guard canEdit else { return }
        guard isDirty else { return }
        guard var n = store.note(by: noteID) else { return }

        n.body = editorText
        n.updatedAt = Date()

        store.updateNote(n)
        note = n
        isDirty = false

        showSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showSavedToast = false
        }
    }

    private func deleteNote() {
        // ✅ Use your store API (handles finalized + SwiftUI refresh correctly)
        store.deleteNote(noteID)
    }

    private func finalizeNote() {
        saveIfNeeded()
        store.finalizeNote(noteID)
        note = store.note(by: noteID)
    }

    // MARK: - Share / Print
    private func shareNote() {
        let text = composePrintableText()
        sharePayload = SharePayload(items: [text])
    }

    private func printNote() {
        EMRPrintHelper.printTextAsPDF(
            composePrintableText(),
            title: titleText,
            jobName: "Medical Note"
        )
    }

    private func composePrintableText() -> String {
        let name = (!patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? patient.nameEnglish
            : (patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Patient" : patient.nameArabic)

        let header = """
        \(name)
        \(store.treatingPhysicianName)
        \(store.clinicName)

        """

        return header + editorText
    }

    private func resignKeyboardThen(_ action: @escaping () -> Void) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            action()
        }
    }

    // MARK: - Sheet payload
    private struct SharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }
}
