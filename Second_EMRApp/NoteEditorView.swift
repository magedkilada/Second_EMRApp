import SwiftUI

struct NoteEditorView: View {
    // MARK: - Inputs
    @Binding var note: RecordNote
    let patient: Patient
    let onSave: (RecordNote) -> Void

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.horizontalSizeClass) private var hSize

    // MARK: - UI State
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @State private var showSavedToast = false
    @State private var showSmartVitalsSheet = false
    @State private var showDeleteConfirm = false
    @State private var showFinalizeWarning = false
    @State private var showBatchPrintMenu = false
    @State private var showBatchPrintPicker = false
    @State private var batchPrintMode: BatchPrintPickerMode = .notes
    @State private var workingVitals: SmartVitalsEntry?
    @State private var showAIAssist = false
    @State private var showTranslate = false
    #if os(iOS)
    @StateObject private var dictation = DictationRecorder()
    #endif

    enum BatchPrintPickerMode {
        case notes
        case prescriptions
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(note.displayTitle).font(.headline)
                        Spacer()
                        #if os(iOS)
                        if !note.isFinalized {
                            dictationButton
                        }
                        #endif
                        if note.isFinalized {
                            Image(systemName: "lock.fill").foregroundStyle(.orange)
                        }
                    }
                    Divider()

                    CursorTextView(
                        text: $note.body,
                        selectedRange: $selectedRange,
                        isEditable: !note.isFinalized
                    )
                    .frame(minHeight: 300)
                }
            }

            bottomButtonsRow
        }
        .padding()
        .onChange(of: note.body) { _, _ in
            if !note.isFinalized {
                onSave(note)
                withAnimation { showSavedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showSavedToast = false }
                }
            }
        }
        .sheet(isPresented: $showSmartVitalsSheet) {
            vitalsEntrySheet
        }
        .confirmationDialog("What would you like to print?", isPresented: $showBatchPrintMenu) {
            Button("Select Notes to Print") {
                batchPrintMode = .notes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showBatchPrintPicker = true
                }
            }
            Button("Select Prescriptions to Print") {
                batchPrintMode = .prescriptions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showBatchPrintPicker = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose notes or prescriptions, then pick which ones to print")
        }
        .sheet(isPresented: $showBatchPrintPicker) {
            BatchPrintPickerSheet(
                patient: patient,
                mode: batchPrintMode,
                store: store,
                physicians: physicians,
                onPrint: { selectedNotes in
                    printSelectedNotes(selectedNotes)
                    showBatchPrintPicker = false
                },
                onCancel: { showBatchPrintPicker = false }
            )
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { store.deleteNote(note.id) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will soft-delete the note. You can restore from backups if needed.")
        }
        .alert("Finalize Note?", isPresented: $showFinalizeWarning) {
            Button("Finalize (Permanent)", role: .destructive) {
                finalizeNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently lock this note. You will NOT be able to edit it again.")
        }
        .sheet(isPresented: $showAIAssist) {
            AIAssistSheet(note: $note, patient: patient, onSave: onSave)
                .environmentObject(store)
        }
        .sheet(isPresented: $showTranslate) {
            TranslateSheet(note: $note, patient: patient, onSave: onSave)
        }
        .overlay(alignment: .top) {
            if showSavedToast {
                Text("Saved")
                    .font(.caption).bold()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.green).foregroundStyle(.white)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Subviews
    private var bottomButtonsRow: some View {
        HStack(spacing: 6) {
            compactBtn("Vitals", icon: "waveform.path.ecg", color: .green) {
                openSmartVitals()
            }

            if !note.isFinalized {
                compactBtn("Finalize", icon: "lock.fill", color: .red) {
                    showFinalizeWarning = true
                }
            } else {
                compactBtn("Locked", icon: "lock.fill", color: .orange) { }
                    .disabled(true)
            }

            Menu {
                Button(action: printCurrentNote) {
                    Label("Print This Note", systemImage: "printer")
                }
                Button(action: { showBatchPrintMenu = true }) {
                    Label("Batch Print...", systemImage: "doc.on.doc")
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "printer").font(.system(size: 14))
                    Text("Print").font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)

            compactBtn("Share", icon: "square.and.arrow.up", color: .gray) {
                shareCurrentNote()
            }

            compactBtn("AI", icon: "brain", color: .purple) {
                showAIAssist = true
            }

            compactBtn("Translate", icon: "globe", color: .blue) {
                showTranslate = true
            }

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "trash").font(.system(size: 14))
                    Text("Delete").font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(note.isFinalized)
        }
    }

    private func compactBtn(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    // MARK: - Dictation

    #if os(iOS)
    private var dictationButton: some View {
        Button {
            dictation.toggleDictation { rawText in
                smartInsertDictation(rawText)
            }
        } label: {
            HStack(spacing: 4) {
                switch dictation.state {
                case .idle:
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    Text("Dictate").font(.caption2)
                case .recording:
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                    Text("Stop").font(.caption2).bold()
                case .transcribing:
                    ProgressView().controlSize(.mini)
                    Text("...").font(.caption2)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(dictation.state == .recording ? Color.red.opacity(0.15) : Color.tertiarySystemGroupedBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(note.isFinalized)
    }

    private func smartInsertDictation(_ rawText: String) {
        guard !rawText.isEmpty else { return }

        // If Claude API is available, use it to organize dictation into template sections
        if ClaudeConfig.isConfigured {
            Task {
                await smartOrganizeDictation(rawText)
            }
        } else {
            // No AI: insert at cursor position
            insertAtCurrentCursor(rawText)
        }
    }

    private func smartOrganizeDictation(_ rawText: String) async {
        let templateSections = note.type.defaultBody
        let system = """
        You are a medical scribe assistant. The physician has dictated text that needs to be \
        inserted into the correct section of a clinical note template. \
        The template sections are:\n\(templateSections)\n\n\
        Rules:\n\
        - Match dictated content to the appropriate template section(s).\n\
        - If the note already has content, merge the new dictation into the correct sections.\n\
        - Preserve ALL existing note content.\n\
        - Output the COMPLETE note body with dictation merged in.\n\
        - Do NOT add information not spoken by the physician.\n\
        - If you cannot determine the section, append the dictation at the cursor position.
        """
        let userMsg = """
        Current note body:
        \(note.body)

        New dictation to insert:
        \(rawText)

        Return the updated note body with the dictation merged into the appropriate sections.
        """

        do {
            let result = try await ClaudeService.shared.generate(
                system: system,
                userMessage: userMsg,
                maxTokens: 3000,
                temperature: 0.1
            )
            await MainActor.run {
                note.body = result
                onSave(note)
            }
        } catch {
            // Fallback: insert at cursor
            await MainActor.run {
                insertAtCurrentCursor(rawText)
            }
        }
    }

    private func insertAtCurrentCursor(_ text: String) {
        let (newText, newRange) = note.body.inserting(text, at: selectedRange)
        note.body = newText
        selectedRange = newRange
        onSave(note)
    }
    #endif

    @ViewBuilder
    private var vitalsEntrySheet: some View {
        if let vitals = workingVitals {
            NavigationStack {
                SmartVitalsEntrySheet(
                    patient: patient,
                    vitals: Binding(get: { vitals }, set: { workingVitals = $0 }),
                    onCancel: { showSmartVitalsSheet = false },
                    onInsertIntoNote: { insertVitalsIntoNote($0); showSmartVitalsSheet = false },
                    onSaveOnly: { store.addOrUpdateVitals($0); showSmartVitalsSheet = false }
                ).environmentObject(store)
            }
        }
    }

    // MARK: - Build header text for current note

    private func buildFullText(for targetNote: RecordNote) -> String {
        let physician = physicians.selectedPhysician
        let header = NoteHeaderBuilder.compactHeader(
            note: targetNote,
            patient: patient,
            physicianName: physician?.name ?? "Unknown",
            clinicName: physician?.clinic ?? "",
            physicianPhone: physician?.phone,
            physicianEmail: physician?.email
        )
        return header + targetNote.body
    }

    // MARK: - Share (direct UIKit — no SwiftUI sheet)

    func shareCurrentNote() {
        let fullText = buildFullText(for: note)
        guard let url = SharePrintBuilder.makeTXTFile(
            filename: "\(patient.nameEnglish)_\(note.displayTitle)",
            text: fullText
        ) else { return }
        // Small delay lets SwiftUI dismiss any internal button state first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            SharePrintPresenter.share(items: [url])
        }
    }

    // MARK: - Print (direct UIKit — no SwiftUI sheet)

    func printCurrentNote() {
        let fullText = buildFullText(for: note)
        guard let url = SharePrintBuilder.makePDFFile(
            filename: "\(patient.nameEnglish)_\(note.displayTitle)",
            title: note.displayTitle,
            body: fullText
        ) else { return }
        SharePrintPresenter.printURL(url, jobName: "\(patient.nameEnglish) - \(note.displayTitle)")
    }

    // MARK: - Batch print selected notes

    func printSelectedNotes(_ notes: [RecordNote]) {
        guard !notes.isEmpty else { return }
        let physician = physicians.selectedPhysician
        var combinedText = ""
        for (index, n) in notes.enumerated() {
            let header = NoteHeaderBuilder.compactHeader(
                note: n,
                patient: patient,
                physicianName: physician?.name ?? "Unknown",
                clinicName: physician?.clinic ?? "",
                physicianPhone: physician?.phone,
                physicianEmail: physician?.email
            )
            combinedText += header + n.body
            if index < notes.count - 1 {
                combinedText += "\n\n\n"
            }
        }
        let title = notes.count == 1 ? notes[0].displayTitle : "Selected (\(notes.count))"
        guard let url = SharePrintBuilder.makePDFFile(
            filename: "Print_\(patient.nameEnglish)_\(title.replacingOccurrences(of: " ", with: "_"))",
            title: "\(title) - \(patient.nameEnglish)",
            body: combinedText
        ) else { return }
        SharePrintPresenter.printURL(url, jobName: "\(patient.nameEnglish) - \(title)")
    }

    // MARK: - Logic Helpers

    func openSmartVitals() {
        showSmartVitalsSheet = false
        workingVitals = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            workingVitals = SmartVitalsEntry(patientID: patient.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showSmartVitalsSheet = true
            }
        }
    }

    func insertVitalsIntoNote(_ vitals: SmartVitalsEntry) {
        store.addOrUpdateVitals(vitals)

        let vitalsText = "\n" + vitals.formattedBlockCompact(patient: patient, useAI: true) + "\n"

        var lines = note.body.components(separatedBy: "\n")

        let fullKeywords = ["physical examination", "objective", "exam:", "examination:"]
        let abbreviatedKeywords = ["pe:", "p.e.:", "p.e:", "o:"]

        var insertIndex: Int?

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for keyword in fullKeywords {
                if lower.contains(keyword) || lower.hasPrefix(keyword) {
                    insertIndex = index + 1
                    break
                }
            }
            if insertIndex != nil { break }
        }

        if insertIndex == nil {
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                for keyword in abbreviatedKeywords {
                    if lower == keyword || lower.hasPrefix(keyword) {
                        insertIndex = index + 1
                        break
                    }
                }
                if insertIndex != nil { break }
            }
        }

        if insertIndex == nil {
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed == "o" || trimmed == "o:" || trimmed == "pe" || trimmed == "pe:" {
                    insertIndex = index + 1
                    break
                }
            }
        }

        if let idx = insertIndex, idx <= lines.count {
            lines.insert(vitalsText, at: idx)
        } else {
            lines.append(vitalsText)
        }

        note.body = lines.joined(separator: "\n")
        onSave(note)
    }

    func finalizeNote() {
        var finalizedNote = note
        finalizedNote.isFinalized = true
        finalizedNote.finalizedAt = Date()
        store.saveNote(finalizedNote)
        note = finalizedNote
        onSave(finalizedNote)
    }
}

#if os(iOS)
// MARK: - Activity View Wrapper (kept for backward compat, but no longer used for notes)
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Batch Print Picker Sheet

struct BatchPrintPickerSheet: View {
    let patient: Patient
    let mode: NoteEditorView.BatchPrintPickerMode
    let store: EMRStore
    let physicians: PhysiciansStore
    let onPrint: ([RecordNote]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<UUID> = []

    private var availableNotes: [RecordNote] {
        let all = store.recordsForPatient(patient.id)
        switch mode {
        case .notes:
            return all.filter { $0.type != .prescription }
        case .prescriptions:
            return all.filter { $0.type == .prescription }
        }
    }

    private var title: String {
        mode == .notes ? "Select Notes" : "Select Prescriptions"
    }

    var body: some View {
        NavigationStack {
            List {
                if availableNotes.isEmpty {
                    Text("No \(mode == .notes ? "notes" : "prescriptions") found.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        Button(selectedIDs.count == availableNotes.count ? "Deselect All" : "Select All") {
                            if selectedIDs.count == availableNotes.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(availableNotes.map(\.id))
                            }
                        }
                    }

                    Section {
                        ForEach(availableNotes) { note in
                            Button {
                                toggleSelection(note.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedIDs.contains(note.id) ? "checkmark.square.fill" : "square")
                                        .font(.title3)
                                        .foregroundStyle(selectedIDs.contains(note.id) ? .blue : .secondary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.displayTitle)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(note.body.prefix(80) + (note.body.count > 80 ? "..." : ""))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    if note.isFinalized {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print (\(selectedIDs.count))") {
                        let selected = availableNotes.filter { selectedIDs.contains($0.id) }
                        onPrint(selected)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}
