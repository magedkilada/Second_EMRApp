import SwiftUI
import UIKit
import Foundation

// NOTE: Requires your existing types:
// - RecordNote (body, createdAt, updatedAt, isFinalized, etc.)
// - Patient (nameEnglish, nameArabic, mrn, dob, gender, phone, etc.)
// - PhysiciansStore (selectedPhysicianName)
// - DictationRecorder (toggleDictation, state, lastError)
// - CursorTextView (UITextView wrapper with selection binding)
// - OpenAIService.shared.generate(instructions:input:)

struct NoteEditorView: View {
    @Binding var note: RecordNote
    let patient: Patient
    let onSave: (RecordNote) -> Void

    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    @StateObject private var dictation = DictationRecorder()

    // Cursor selection tracking
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)

    // MARK: - AI / Translation State
    @State private var showAIResultSheet = false
    @State private var showAIModeSheet = false

    @State private var aiResultText: String = ""
    @State private var aiQuestion: String = ""

    @State private var isAIWorking: Bool = false
    @State private var useNoteContextForAI: Bool = true

    @State private var targetLanguage: String = "Arabic"
    private let languages: [String] = ["Arabic", "English", "French", "German", "Spanish", "Italian"]

    // MARK: - Header helpers

    private var patientDisplayName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ar.isEmpty { return ar }
        return "Patient"
    }

    private var clinicName: String { "Neurosurgery" }

    private var physicianName: String {
        physicians.selectedPhysicianName ?? "—"
    }

    private var mrnText: String {
        let m = patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "—" : m
    }

    private var phoneText: String {
        let p = patient.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? "—" : p
    }

    private var dobText: String {
        patient.dob.formatted(date: .abbreviated, time: .omitted)
    }

    private var sexText: String {
        patient.gender.rawValue
    }

    private var createdText: String {
        note.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var updatedText: String {
        note.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header card
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(patientDisplayName)
                        .font(.headline)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 4) {
                        headerLine(label: "MRN", value: mrnText)
                        headerLine(label: "DOB", value: dobText)
                        headerLine(label: "Sex", value: sexText)
                        headerLine(label: "Clinic", value: clinicName)
                        headerLine(label: "Physician", value: physicianName)
                        headerLine(label: "Note Created", value: createdText)
                        headerLine(label: "Note Updated", value: updatedText)

                        if phoneText != "—" {
                            headerLine(label: "Phone", value: phoneText)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            // Editor + bottom bar
            VStack(spacing: 0) {

                CursorTextView(
                    text: $note.body,
                    selectedRange: $selectedRange,
                    isEditable: !note.isFinalized
                )
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .padding(.bottom, 8)

                controlsBar
            }

            if let err = dictation.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if note.isFinalized {
                Text("This note is finalized. You can still use AI and Translate, but editing is locked.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .onAppear {
            // Put cursor at end the first time this editor opens
            if selectedRange.location == 0 && selectedRange.length == 0 && !note.body.isEmpty {
                selectedRange = NSRange(location: (note.body as NSString).length, length: 0)
            }
        }

        // ✅ Sheet 1: AI / Translation result viewer
        .sheet(isPresented: $showAIResultSheet) {
            NavigationStack {
                ScrollView {
                    Text(aiResultText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .navigationTitle("AI / Translation")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Copy") { UIPasteboard.general.string = aiResultText }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showAIResultSheet = false }
                    }
                }
            }
        }

        // ✅ Sheet 2: Ask AI (question box)
        .sheet(isPresented: $showAIModeSheet) {
            NavigationStack {
                Form {
                    Section("Mode") {
                        Toggle("Use this note as context", isOn: $useNoteContextForAI)
                    }

                    Section("Question") {
                        TextField("Type your question…", text: $aiQuestion, axis: .vertical)
                            .lineLimit(3...8)
                    }

                    Section {
                        Button {
                            Task { await runAIQuestion() }
                        } label: {
                            Label("Ask", systemImage: "paperplane.fill")
                        }
                        .disabled(aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAIWorking)
                    }
                }
                .navigationTitle("Ask AI")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showAIModeSheet = false }
                    }
                }
            }
        }
    }

    // MARK: - Bottom controls bar

    private var controlsBar: some View {
        HStack(spacing: 10) {

            // Save (only meaningful if editable)
            Button("Save") {
                var n = note
                n.updatedAt = Date()
                onSave(n)
            }
            .buttonStyle(.borderedProminent)
            .disabled(note.isFinalized)

            // Dictation (disable if finalized OR transcribing)
            Button {
                dictation.toggleDictation { transcript in
                    let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    insertTranscript(t)
                }
            } label: {
                if isPhone {
                    Image(systemName: dictation.state == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                } else {
                    Label(
                        dictation.state == .recording ? "Stop" : "Dictate",
                        systemImage: dictation.state == .recording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                }
            }
            .buttonStyle(.bordered)
            .disabled(note.isFinalized || dictation.state == .transcribing)

            // AI Menu (works even if note is finalized)
            Menu {
                Button {
                    showAIModeSheet = true
                } label: {
                    Label("Ask a Question", systemImage: "questionmark.bubble")
                }

                Button {
                    Task { await aiAssistImprove() }
                } label: {
                    Label("Improve Note (preview)", systemImage: "sparkles")
                }
            } label: {
                if isPhone {
                    Image(systemName: "sparkles").font(.title3)
                } else {
                    Label("AI", systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAIWorking)

            // Translate menu (works even if note is finalized)
            Menu {
                Picker("Language", selection: $targetLanguage) {
                    ForEach(languages, id: \.self) { Text($0).tag($0) }
                }

                Button {
                    Task { await runTranslate() }
                } label: {
                    Label("Translate Now", systemImage: "globe")
                }
            } label: {
                if isPhone {
                    Image(systemName: "globe").font(.title3)
                } else {
                    Label("Translate", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAIWorking)

            if isAIWorking || dictation.state == .transcribing {
                ProgressView().scaleEffect(0.9)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helper line

    private func headerLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):").bold()
            Text(value).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Insert dictation at cursor (only if editable)

    private func insertTranscript(_ t: String) {
        guard !note.isFinalized else { return }

        let ns = note.body as NSString
        let safeLoc = max(0, min(selectedRange.location, ns.length))
        let safeLen = max(0, min(selectedRange.length, ns.length - safeLoc))
        let safeRange = NSRange(location: safeLoc, length: safeLen)

        var leading = ""
        if safeLoc > 0 {
            let prevChar = ns.substring(with: NSRange(location: safeLoc - 1, length: 1))
            if prevChar != "\n" && prevChar != " " && prevChar != "\t" {
                leading = " "
            }
        }

        let insert = leading + t
        note.body = ns.replacingCharacters(in: safeRange, with: insert)
        selectedRange = NSRange(location: safeLoc + (insert as NSString).length, length: 0)
    }

    // MARK: - AI / Translation Actions

    @MainActor
    private func runAIQuestion() async {
        let q = aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        isAIWorking = true
        defer { isAIWorking = false }

        let context = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let input: String

        if useNoteContextForAI, !context.isEmpty {
            input = """
NOTE:
\(context)

QUESTION:
\(q)
"""
        } else {
            input = q
        }

        do {
            let result = try await OpenAIService.shared.generate(
                instructions: """
You are a neurosurgery assistant.
Answer clearly and clinically.
If the question is about management, provide structured options and cautions.
If details are missing, ask clarifying questions.
""",
                input: input
            )
            aiResultText = result
            showAIModeSheet = false
            showAIResultSheet = true
        } catch {
            dictation.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func aiAssistImprove() async {
        let text = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isAIWorking = true
        defer { isAIWorking = false }

        do {
            let improved = try await OpenAIService.shared.generate(
                instructions: """
You are a neurosurgery assistant.
Improve clarity, structure, and professionalism.
Preserve all medical facts.
Do NOT remove headings.
Return only the improved note text.
""",
                input: text
            )

            aiResultText = improved
            showAIResultSheet = true
        } catch {
            dictation.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func runTranslate() async {
        let text = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isAIWorking = true
        defer { isAIWorking = false }

        do {
            let translated = try await OpenAIService.shared.generate(
                instructions: """
Translate the following medical note into \(targetLanguage).
Preserve headings and medical meaning.
Use professional medical language.
""",
                input: text
            )

            aiResultText = translated
            showAIResultSheet = true
        } catch {
            dictation.lastError = error.localizedDescription
        }
    }
}
