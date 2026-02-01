import SwiftUI

struct AIAssistSheet: View {
    @Binding var note: RecordNote
    let patient: Patient
    let onSave: (RecordNote) -> Void
    @EnvironmentObject private var store: EMRStore

    @Environment(\.dismiss) private var dismiss

    enum AIMode: String, CaseIterable {
        case refine = "Refine Note"
        case askNote = "Ask About Note"
        case askAnything = "Ask Anything"

        var icon: String {
            switch self {
            case .refine: return "wand.and.stars"
            case .askNote: return "doc.questionmark"
            case .askAnything: return "sparkles"
            }
        }
    }

    enum AIModel: String, CaseIterable {
        case claude = "Claude"
        case gpt = "GPT-4o"

        var icon: String {
            switch self {
            case .claude: return "brain.head.profile"
            case .gpt: return "brain"
            }
        }
    }

    @State private var mode: AIMode = .refine
    @State private var selectedModel: AIModel = .claude
    @State private var userPrompt: String = ""
    @State private var aiResponse: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String = ""
    @State private var showReplaceConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(AIMode.allCases, id: \.self) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)

                // Model picker
                HStack(spacing: 8) {
                    Text("Model:").font(.caption).foregroundStyle(.secondary)
                    Picker("Model", selection: $selectedModel) {
                        ForEach(AIModel.allCases, id: \.self) { model in
                            Label(model.rawValue, systemImage: model.icon).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Instructions
                        modeDescription

                        // User input (for askNote and askAnything)
                        if mode == .askNote || mode == .askAnything {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your Question").font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $userPrompt)
                                    .frame(minHeight: 60, maxHeight: 120)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                            }
                        }

                        if mode == .refine {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Refinement Instructions (optional)").font(.caption).foregroundStyle(.secondary)
                                TextField("e.g. Make it more concise, fix grammar...", text: $userPrompt)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Submit button
                        Button {
                            Task { await runAI() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text(isLoading ? "Processing..." : "Send to \(selectedModel.rawValue)")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isLoading || (mode != .refine && userPrompt.trimmingCharacters(in: .whitespaces).isEmpty))

                        // Error
                        if !errorMessage.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                Text(errorMessage).font(.caption).foregroundStyle(.red)
                            }
                        }

                        // Response
                        if !aiResponse.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("AI Response").font(.headline)
                                    Spacer()
                                    Button {
                                        aiResponse = ""
                                        errorMessage = ""
                                    } label: {
                                        Label("Clear", systemImage: "xmark.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.secondary)
                                }

                                Text(aiResponse)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color.secondarySystemGroupedBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                // Action buttons for refine mode
                                if mode == .refine {
                                    HStack(spacing: 12) {
                                        Button {
                                            showReplaceConfirm = true
                                        } label: {
                                            Label("Replace Note", systemImage: "arrow.triangle.2.circlepath")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)

                                        Button {
                                            appendToNote(aiResponse)
                                        } label: {
                                            Label("Append to Note", systemImage: "plus.square.on.square")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                    }
                                }

                                // Copy button for all modes
                                Button {
                                    PlatformPasteboard.copy(aiResponse)
                                } label: {
                                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("AI Assist")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Replace Note Body?", isPresented: $showReplaceConfirm) {
                Button("Replace", role: .destructive) {
                    replaceNoteBody(aiResponse)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will replace the entire note body with the AI-refined version. This cannot be undone.")
            }
        }
    }

    // MARK: - Mode description

    private var modeDescription: some View {
        Group {
            switch mode {
            case .refine:
                Label("AI will refine and improve the current note. You can replace the note or use parts of the result.", systemImage: "wand.and.stars")
                    .font(.caption).foregroundStyle(.secondary)
            case .askNote:
                Label("Ask questions about the current note content.", systemImage: "doc.questionmark")
                    .font(.caption).foregroundStyle(.secondary)
            case .askAnything:
                Label("Ask any medical or clinical question.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - AI Logic

    private func runAI() async {
        isLoading = true
        errorMessage = ""

        do {
            let system: String
            let input: String

            switch mode {
            case .refine:
                system = """
                You are a medical documentation assistant. Refine and improve the following clinical note. \
                Keep the same structure and medical content but improve clarity, grammar, and formatting. \
                Do not add fictional information. Only output the refined note text, no preamble.
                """
                input = userPrompt.isEmpty
                    ? "Please refine this clinical note:\n\n\(note.body)"
                    : "Please refine this clinical note with these instructions: \(userPrompt)\n\nNote:\n\(note.body)"

            case .askNote:
                system = """
                You are a medical documentation assistant. Answer questions about the provided clinical note. \
                Be concise and accurate. If information is not in the note, say so.
                """
                input = "Clinical note:\n\n\(note.body)\n\nQuestion: \(userPrompt)"

            case .askAnything:
                system = """
                You are a knowledgeable medical assistant. Provide accurate, evidence-based medical information. \
                Always include a disclaimer that this is AI-generated and should not replace clinical judgment.
                """
                input = userPrompt
            }

            let result: String
            switch selectedModel {
            case .claude:
                result = try await ClaudeService.shared.generate(
                    system: system,
                    userMessage: input,
                    maxTokens: 3000
                )
            case .gpt:
                result = try await OpenAIService.shared.generate(
                    instructions: system,
                    input: input,
                    maxOutputTokens: 3000,
                    temperature: 0.2
                )
            }

            await MainActor.run {
                aiResponse = result
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    // MARK: - Note Actions

    private func replaceNoteBody(_ text: String) {
        guard !note.isFinalized else { return }
        note.body = text
        onSave(note)
    }

    private func appendToNote(_ text: String) {
        guard !note.isFinalized else { return }
        note.body += "\n\n--- AI Assist ---\n" + text + "\n"
        onSave(note)
    }
}

