import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AIAssistView: View {

    // MARK: - Modes

    enum TopMode: String, CaseIterable, Identifiable {
        case assist = "Assist"
        case translate = "Translate"
        var id: String { rawValue }
    }

    enum AssistScope: String, CaseIterable, Identifiable {
        case whole = "Whole Note"
        case section = "Section"
        var id: String { rawValue }
    }

    enum WholeAction: String, CaseIterable, Identifiable {
        case improve = "Improve clarity"
        case shorten = "Shorten"
        case expand = "Expand"
        case grammar = "Correct grammar only"
        case summarize = "Summarize / Impression"
        var id: String { rawValue }
    }

    enum ApplyStyle: String, CaseIterable, Identifiable {
        case replace = "Replace"
        case append = "Append"
        case prepend = "Insert at top"
        var id: String { rawValue }
    }

    enum TranslateLanguage: String, CaseIterable, Identifiable {
        case arabic = "Arabic"
        case english = "English"
        case french = "French"
        case german = "German"
        case italian = "Italian"
        case spanish = "Spanish"
        var id: String { rawValue }

        var instructionName: String { rawValue }
    }

    // MARK: - Inputs

    let note: RecordNote
    let onApplyNewBody: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - UI State

    @State private var topMode: TopMode = .assist

    // Assist state
    @State private var assistScope: AssistScope = .whole
    @State private var wholeAction: WholeAction = .improve
    @State private var applyStyle: ApplyStyle = .replace
    @State private var selectedHeader: String = ""
    @State private var sectionInsertBelowHeader: Bool = true

    // Translate state
    @State private var targetLanguage: TranslateLanguage = .arabic
    @State private var translateApplyStyle: ApplyStyle = .replace

    // Shared
    @State private var extraInstruction: String = ""
    @State private var output: String = ""
    @State private var isRunning = false
    @State private var errorMessage: String?

    private var isFinalized: Bool { note.isFinalized }

    private var headersForThisNote: [String] {
        extractHeaders(from: note.type.defaultBody)
    }

    // MARK: - View

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {

                    // Top toggle: Assist / Translate
                    Picker("", selection: $topMode) {
                        ForEach(TopMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    // What AI sees
                    GroupBox("What AI sees") {
                        Text(note.body)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Mode-specific UI
                    if topMode == .assist {
                        assistControls
                    } else {
                        translateControls
                    }

                    // Output preview
                    aiOutputPreview

                    // Error (if any)
                    if let err = errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("AI Assist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    // MARK: - Assist Controls

    private var assistControls: some View {
        GroupBox("Assist") {
            VStack(alignment: .leading, spacing: 10) {

                Picker("Scope", selection: $assistScope) {
                    ForEach(AssistScope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                if assistScope == .whole {
                    Picker("Action", selection: $wholeAction) {
                        ForEach(WholeAction.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }

                    Picker("Apply as", selection: $applyStyle) {
                        ForEach(ApplyStyle.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                } else {
                    Picker("Section", selection: $selectedHeader) {
                        ForEach(headersForThisNote, id: \.self) { h in
                            Text(h).tag(h)
                        }
                    }
                    .onAppear {
                        if selectedHeader.isEmpty {
                            selectedHeader = headersForThisNote.first ?? ""
                        }
                    }

                    Toggle("Insert below header (otherwise replace section)", isOn: $sectionInsertBelowHeader)
                        .disabled(headersForThisNote.isEmpty)
                }

                TextField("Extra instruction (optional)…", text: $extraInstruction)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(isRunning ? "Working…" : "Run GPT-4.1") {
                        Task { await runAI() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)

                    Spacer()

                    Button("Copy Output") {
                        PlatformPasteboard.copy(output)
                    }
                    .buttonStyle(.bordered)
                    .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Apply to Note") {
                        applyOutputToNote()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFinalized || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isFinalized {
                    Text("This note is finalized — you can run AI and copy output, but you cannot apply changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Translate Controls

    private var translateControls: some View {
        GroupBox("Translate") {
            VStack(alignment: .leading, spacing: 10) {

                Picker("Target language", selection: $targetLanguage) {
                    ForEach(TranslateLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }

                Picker("Apply as", selection: $translateApplyStyle) {
                    ForEach(ApplyStyle.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }

                TextField("Extra instruction (optional)…", text: $extraInstruction)
                    .textFieldStyle(.roundedBorder)

                Text("Headers stay in English exactly (e.g., “SUBJECTIVE:”); content is translated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(isRunning ? "Working…" : "Translate with GPT-4.1") {
                        Task { await runAI() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)

                    Spacer()

                    Button("Copy Output") {
                        PlatformPasteboard.copy(output)
                    }
                    .buttonStyle(.bordered)
                    .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Apply to Note") {
                        applyOutputToNote()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFinalized || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if isFinalized {
                    Text("This note is finalized — translation can be generated and copied, but cannot be applied.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Output Preview

    private var aiOutputPreview: some View {
        GroupBox("AI Output (preview)") {
            TextEditor(text: $output)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.secondary.opacity(0.35))
                )
        }
    }

    // MARK: - Run AI

    private func runAI() async {
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        let sys = systemPrompt()
        let user = userPrompt()

        do {
            let text = try await OpenAIService.shared.generate(
                instructions: sys,
                input: user,
                maxOutputTokens: 1800,
                temperature: 0.2
            )
            output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func systemPrompt() -> String {
        """
You are assisting a neurosurgeon writing clinical documentation.
Rules:
- Do NOT invent facts, vitals, labs, meds, diagnoses, imaging, or timelines.
- If information is missing, write: "Not documented" (or keep placeholders) rather than guessing.
- Preserve medical tone. Prefer concise bullet points when appropriate.
- Output ONLY the requested text (no meta commentary).
"""
    }

    private func userPrompt() -> String {
        let instruction = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        switch topMode {

        case .assist:
            switch assistScope {

            case .whole:
                return """
    NOTE TYPE: \(note.type.rawValue)
    REQUEST: \(wholeAction.rawValue)
    \(instruction.isEmpty ? "" : "EXTRA: \(instruction)\n")
    NOTE TEXT:
    \(note.body)
    """

            case .section:
                let h = selectedHeader.isEmpty
                    ? (headersForThisNote.first ?? "")
                    : selectedHeader

                return """
    NOTE TYPE: \(note.type.rawValue)
    REQUEST: Update ONLY this section: "\(h)"
    MODE: \(sectionInsertBelowHeader
        ? "Generate new content to insert below the header"
        : "Generate replacement content for the section")
    \(instruction.isEmpty ? "" : "EXTRA: \(instruction)\n")
    CURRENT NOTE TEXT:
    \(note.body)

    Return ONLY the section content (do not repeat the entire note).
    If you include the header, include it exactly as "\(h)".
    """
            }

        case .translate:
            return """
    TASK: Translate the NOTE TEXT into \(targetLanguage.instructionName).
    RULES:
    - Keep ALL headers in English EXACTLY as written (do NOT translate headers).
    - Translate ONLY the content under headers.
    - Do NOT invent facts.
    \(instruction.isEmpty ? "" : "EXTRA: \(instruction)\n")
    NOTE TEXT:
    \(note.body)
    """
        }
    }

    // MARK: - Apply Output

    private func applyOutputToNote() {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        switch topMode {
        case .assist:
            switch assistScope {
            case .whole:
                switch applyStyle {
                case .replace:
                    onApplyNewBody(cleaned)
                case .append:
                    onApplyNewBody(note.body + "\n\n" + cleaned)
                case .prepend:
                    onApplyNewBody(cleaned + "\n\n" + note.body)
                }
            case .section:
                guard !selectedHeader.isEmpty else { return }
                let newBody = sectionInsertBelowHeader
                    ? insertBelowHeader(in: note.body, header: selectedHeader, insertion: cleaned)
                    : replaceSection(in: note.body, header: selectedHeader, replacement: cleaned)
                onApplyNewBody(newBody)
            }

        case .translate:
            switch translateApplyStyle {
            case .replace:
                onApplyNewBody(cleaned)
            case .append:
                onApplyNewBody(note.body + "\n\n" + cleaned)
            case .prepend:
                onApplyNewBody(cleaned + "\n\n" + note.body)
            }
        }
    }

    // MARK: - Section Helpers

    private func extractHeaders(from template: String) -> [String] {
        // Lines that end with ":" are treated as headers
        let lines = template.components(separatedBy: .newlines)
        let headers = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasSuffix(":") }
        return Array(headers.prefix(40))
    }

    private func insertBelowHeader(in body: String, header: String, insertion: String) -> String {
        guard let range = body.range(of: header) else {
            // header not found -> append header + insertion
            return body + "\n\n" + header + "\n" + insertion
        }

        // Find end of the header line (insert after that line, not mid-line)
        let afterHeader = range.upperBound
        // Insert immediately after the header token; add newline to ensure separation
        return body[..<afterHeader] + "\n" + insertion + "\n" + body[afterHeader...]
    }

    private func replaceSection(in body: String, header: String, replacement: String) -> String {
        let lines = body.components(separatedBy: .newlines)

        // Find header line index (exact match after trimming)
        guard let startIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == header }) else {
            return body + "\n\n" + header + "\n" + replacement
        }

        // End at next header-like line (ends with ":") after start
        var endIdx = lines.count
        if startIdx + 1 < lines.count {
            for i in (startIdx + 1)..<lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasSuffix(":") {
                    endIdx = i
                    break
                }
            }
        }

        var out = lines
        // Keep the header line, replace everything until next header
        out.replaceSubrange((startIdx + 1)..<endIdx, with: [replacement])

        return out.joined(separator: "\n")
    }
}
