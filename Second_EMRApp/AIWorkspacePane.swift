import SwiftUI
import UIKit

struct AIWorkspacePane: View {

    // MARK: - Inputs
    @ObservedObject var store: EMRStore
    let selectedPatientID: UUID?

    @Binding var contextText: String
    let selectedReferenceTitle: String?

    // MARK: - Local AI state (owned here)
    @State private var prompt: String = ""
    @State private var output: String = ""

    // MARK: - Mode
    enum Mode: String, CaseIterable, Identifiable {
        case ask = "Ask"
        case translate = "Translate"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .ask

    var body: some View {
        VStack(spacing: 12) {

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            GroupBox("Context (what AI sees)") {
                VStack(alignment: .leading, spacing: 8) {

                    if let title = selectedReferenceTitle, !title.isEmpty {
                        Text("Selected reference: \(title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextEditor(text: $contextText)
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))

                    HStack {
                        Spacer()
                        Button("Clear") { contextText = "" }
                    }
                }
            }

            GroupBox(mode == .ask ? "Ask AI" : "Translate") {
                VStack(alignment: .leading, spacing: 8) {

                    if mode == .ask {
                        TextField("Type your question…", text: $prompt)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text("Translate the context above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Instruction: Do not invent. If unsure, say so.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button(mode == .ask ? "Ask" : "Translate") {
                            runAI()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear") {
                            prompt = ""
                            output = ""
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Copy Output") {
                            UIPasteboard.general.string = output
                        }
                        .buttonStyle(.bordered)

                        Button("Save as Note") {
                            saveAsNote()
                        }
                        .buttonStyle(.bordered)
                        .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    TextEditor(text: $output)
                        .frame(minHeight: 180)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .disabled(false)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    // MARK: - AI (stub for now)
    private func runAI() {
        // Placeholder until OpenAI service is wired.
        // We keep UI working first.
        if mode == .translate {
            output = """
            [TRANSLATION PLACEHOLDER]
            \(contextText)
            """
        } else {
            output = """
            [AI ANSWER PLACEHOLDER]
            Q: \(prompt)
            Context length: \(contextText.count) chars
            """
        }
    }

    // MARK: - Save output as a note
    private func saveAsNote() {
        guard let pid = selectedPatientID else { return }

        let caption = "⚠️ This content was generated/translated by AI. Errors may occur. Please verify.\n\n"

        var note = RecordNote(patientID: pid, type: .blank)
        note.title = "AI Output"
        note.body = caption + output
        note.updatedAt = Date()

        store.notes.insert(note, at: 0)
        store.selectedNoteID = note.id
        store.lastModified = Date()
    }
}
