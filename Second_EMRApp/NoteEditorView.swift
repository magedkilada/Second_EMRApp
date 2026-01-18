//
//  NoteEditorView.swift
//  Second_EMRApp
//

import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
#endif

struct NoteEditorView: View {

    // MARK: - Inputs
    let patient: Patient
    let noteID: UUID

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    // MARK: - Local editor state
    @State private var titleText: String = ""
    @State private var bodyText: String = ""
    @State private var hasLoaded: Bool = false

    // Auto-save debounce
    @State private var autoSaveWorkItem: DispatchWorkItem? = nil

    // Header visibility
    @State private var showHeaderOnScreen: Bool = false

    // Share
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    // Finalize confirm
    @State private var showConfirmFinalize: Bool = false
    
    @State private var showBatchPrintSheet: Bool = false

    // MARK: - Derived
    private var noteIndex: Int? {
        store.notes.firstIndex { $0.id == noteID && $0.patientID == patient.id && !$0.isDeleted }
    }

    private var currentNote: RecordNote? {
        guard let idx = noteIndex else { return nil }
        return store.notes[idx]
    }

    private var createdAt: Date { currentNote?.createdAt ?? Date() }
    private var updatedAt: Date { currentNote?.updatedAt ?? Date() }

    private var isFinalized: Bool {
        guard let idx = noteIndex else { return false }
        return store.notes[idx].isFinalized
    }

    /// Baseline: only Blank note shows Title field.
    /// If your RecordNote has a real type, replace this with:
    /// `return currentNote?.type == .blank` (or whatever you use)
    private var isBlankNote: Bool {
        return true
    }

    // MARK: - UI
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // 1) Header (shown or hidden row)
            if showHeaderOnScreen {
                headerView
            } else {
                headerHiddenRow
            }

            // 2) Title (blank notes only)
            if isBlankNote {
                TextField("Title", text: $titleText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isFinalized)
                    .onChange(of: titleText) { _, _ in
                        if !isFinalized { scheduleAutoSave() }
                    }
            }

            // 3) Body editor (single editor)
            TextEditor(text: $bodyText)
                .font(.body)
                .frame(minHeight: 300)
                .disabled(isFinalized)
                .opacity(isFinalized ? 0.85 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: bodyText) { _, _ in
                    if !isFinalized { scheduleAutoSave() }
                }
                .overlay(alignment: .bottomTrailing) {
                    actionButtons
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                }
        }
        .padding()
        .onAppear { loadFromStoreIfNeeded() }
        .onChange(of: noteID) { _, _ in
            hasLoaded = false
            loadFromStoreIfNeeded()
        }
        .sheet(isPresented: $showShareSheet) {
            EMRShareSheetView(items: shareItems)
        }
        .sheet(isPresented: $showBatchPrintSheet) {
            BatchPrintView(patient: patient)
                .environmentObject(store)
        }
    }

    // MARK: - Header hidden row (compact)
    private var headerHiddenRow: some View {
        HStack(spacing: 10) {
            Text("Header hidden (included in Share/Print).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Show") { showHeaderOnScreen = true }
                .font(.footnote)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Header (compact, horizontal)
    private var headerView: some View {
        HStack(alignment: .top, spacing: 14) {

            VStack(alignment: .leading, spacing: 4) {
                headerLine("Created", formatDateTime(createdAt))
                headerLine("Updated", formatDateTime(updatedAt))

                Divider().opacity(0.25).padding(.vertical, 4)

                headerLine("Physician", physicianNameText())
                headerLine("Clinic", clinicNameText())
                headerLine("Physician phone", physicianPhoneText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.25)

            VStack(alignment: .leading, spacing: 4) {
                headerLine("Patient", patientDisplayNameText())
                headerLine("DOB", patientDOBText())
                headerLine("Sex", patientSexText())
                headerLine("MRN", patientMRNText())
                headerLine("Phone", patientPhoneText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .padding(.bottom, 6)
    }

    private func headerLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):").fontWeight(.semibold)
            Text(value.isEmpty ? "—" : value)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom-right action buttons
    private var actionButtons: some View {
        HStack(spacing: 12) {

            Button { saveDraftNow() } label: {
                Image(systemName: "tray.and.arrow.down.fill")
            }
            .disabled(isFinalized)

            Button { shareNote() } label: {
                Image(systemName: "square.and.arrow.up")
            }

            Menu {
                Button {
                    printNote()
                } label: {
                    Label("Print This Note", systemImage: "printer")
                }

                Button {
                    showBatchPrintSheet = true
                } label: {
                    Label("Batch Print…", systemImage: "printer.fill")
                }

            } label: {
                Image(systemName: "printer")
            }

            // placeholders to keep layout reserved for later
            Button { /* AI later */ } label: { Image(systemName: "sparkles") }
                .disabled(true).opacity(0.35)

            Button { /* Translate later */ } label: { Image(systemName: "globe") }
                .disabled(true).opacity(0.35)

            Button(role: .destructive) { clearEditor() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .disabled(isFinalized)

            // ✅ Insert Latest Vitals (same row, same size, no overlap)
            Button {
                insertLatestVitals()
            } label: {
                Image(systemName: "heart.text.square")
            }
            .disabled(isFinalized)

            Button { showConfirmFinalize = true } label: {
                Image(systemName: "checkmark.seal.fill")
            }
            .disabled(isFinalized)
            .confirmationDialog("Finalize this note?", isPresented: $showConfirmFinalize) {
                Button("Finalize", role: .destructive) { finalizeNow() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Finalized notes become read-only and cannot be deleted.")
            }
        }
        .font(.title3)
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }
    
    private func insertLatestVitals() {
        guard !isFinalized else { return }

        // Find latest vitals for this patient
        guard let v = store.vitals
            .filter({ $0.patientID == patient.id })
            .sorted(by: { $0.measuredAt > $1.measuredAt })
            .first
        else {
            store.lastErrorMessage = "No vitals available."
            return
        }

        // Build vitals line with derived values
        var parts: [String] = []

        if let bp = v.bpString { parts.append("BP \(bp)") }
        if let hr = v.heartRate { parts.append("HR \(hr)") }
        if let s = v.spo2 { parts.append("SpO₂ \(s)%") }
        if let t = v.tempC { parts.append(String(format: "T %.1f°C", t)) }
        if let w = v.weightKg { parts.append(String(format: "Wt %.1f kg", w)) }
        if let h = v.heightCm { parts.append(String(format: "Ht %.0f cm", h)) }
        if let bmi = v.bmi, bmi.isFinite { parts.append(String(format: "BMI %.1f", bmi)) }
        if let hc = v.headCircumferenceCm { parts.append(String(format: "HC %.1f cm", hc)) }

        let vitalsLine =
            "Vitals (\(v.measuredAt.formatted(date: .abbreviated, time: .shortened))): "
            + parts.joined(separator: " • ")

        // Insert immediately into editor text (no reopen needed)
        bodyText = smartInsertVitals(vitalsLine, into: bodyText)


    }
    
    private func smartInsertVitals(_ vitalsLine: String, into text: String) -> String {
        // Try targets in order
        let targets = [
            "PHYSICAL EXAMINATION:",
            "OBJECTIVE:",
            "VITALS:",
            "Physical Examination:",
            "Objective:",
            "Vitals:"
        ]

        for target in targets {
            if let range = text.range(of: target) {
                // insert on the next line after the header
                let insertPoint = range.upperBound
                let afterHeader = text[insertPoint...]
                let prefix = text[..<insertPoint]

                // If header already has content on same line, just add newline first
                let needsNewLine = !(afterHeader.hasPrefix("\n"))
                let glue = needsNewLine ? "\n" : ""

                // Avoid duplicate if same vitals already present (basic check)
                if text.contains(vitalsLine) { return text }

                return String(prefix) + glue + vitalsLine + "\n" + String(afterHeader)
            }
        }

        // Fallback: append at end
        if text.contains(vitalsLine) { return text }
        return text + "\n\n" + vitalsLine + "\n"
    }
    // MARK: - Actions
    private func clearEditor() {
        if isBlankNote { titleText = "" }
        bodyText = ""
        saveDraftNow()
    }

    private func finalizeNow() {
        guard let idx = noteIndex else { return }
        guard !store.notes[idx].isFinalized else { return }

        var n = store.notes[idx]
        n.isFinalized = true
        n.updatedAt = Date()

        store.notes[idx] = n
        store.saveNotes()
    }

    // MARK: - Share / Print
    private func shareNote() {
        do {
            let url = try exportToTempTextFile()
            shareItems = [url]     // ✅ share the FILE (fixes your AirDrop issue)
            showShareSheet = true
        } catch {
            store.lastErrorMessage = "Share failed: \(error.localizedDescription)"
        }
    }

    private func exportToTempTextFile() throws -> URL {
        let text = exportText()

        let dir = FileManager.default.temporaryDirectory
        let safeName = patientDisplayNameText().replacingOccurrences(of: " ", with: "_")
        let fileURL = dir.appendingPathComponent("\(safeName)_\(noteID.uuidString.prefix(6)).txt")

        try text.data(using: .utf8)?.write(to: fileURL, options: [.atomic])
        return fileURL
    }
    
    private func exportHTMLForPrint() -> String {

        // Build the same exported content (patient + physician + note title + body)
        let plain = exportText()

        // Escape HTML special chars
        let escaped = escapeHTML(plain)

        // Preserve single spacing using <br/>
        let lines = escaped.components(separatedBy: "\n")
        let bodyHTML = lines
            .map { $0.isEmpty ? "&nbsp;" : $0 }
            .joined(separator: "<br/>")

        return """
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
          body {
            font-family: -apple-system, Helvetica, Arial;
            font-size: 9.75pt;   /* MATCHES batch print */
            line-height: 1.15;
          }
            .wrap {
              white-space: normal;
            }
          </style>
        </head>
        <body>
          <div class="wrap">\(bodyHTML)</div>
        </body>
        </html>
        """
    }
    // MARK: - Helpers for HTML print

    private func escapeHTML(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func isHeadingLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }

        // Treat ALL-CAPS ending with ":" as headings (your template style)
        // Examples: "CHIEF COMPLAINT:", "PAST MEDICAL HISTORY:", "OBJECTIVE:", etc.
        // Also accept common title lines like "History & Physical (H&P)"
        if t.hasSuffix(":") {
            let letters = t.filter { $0.isLetter }
            if letters.isEmpty { return false }
            return letters == letters.uppercased()
        }

        // Optional: treat note type title line as a "heading"
        // (not bold, just slightly larger if you set 13pt)
        if t.contains("(H&P)") || t.contains("SOAP") || t.contains("Operative") || t.contains("Discharge") || t.contains("EEG") {
            // But avoid making metadata lines headings
            if t.hasPrefix("Patient:") || t.hasPrefix("MRN:") || t.hasPrefix("DOB:") || t.hasPrefix("Sex:") { return false }
            if t.hasPrefix("Physician:") || t.hasPrefix("Clinic:") || t.hasPrefix("Phone:") { return false }
            return true
        }

        return false
    }

    /// Rules:
    /// - Make the first “History & Physical (H&P)” / “SOAP / Progress Note” line a bigger semi-bold title.
    /// - Make ANY ALL-CAPS heading that ends with ":" semi-bold (CHIEF COMPLAINT:, PLAN:, etc).
    /// - Everything else stays normal.
    private func styleLineAsHTML(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Note type title line (examples: "History & Physical (H&P)", "SOAP / Progress Note")
        if trimmed == "History & Physical (H&P)" || trimmed == "SOAP / Progress Note"
            || trimmed == "Operative Note" || trimmed == "Discharge Summary" || trimmed == "EEG Report" {
            return #"<span class="noteTitle">"# + line + #"</span>"#
        }

        // Section headings like "CHIEF COMPLAINT:" "PAST MEDICAL HISTORY:" etc
        if trimmed.hasSuffix(":") {
            // consider it a heading if it is mostly uppercase / symbols
            let upper = trimmed.uppercased()
            let looksUpper = (trimmed == upper)
            if looksUpper {
                return #"<span class="heading">"# + line + #"</span>"#
            }
        }

        // Everything else normal
        return line
    }

    private func exportText() -> String {
        var lines: [String] = []
        lines.append("Patient: \(patientDisplayNameText())")
        lines.append("MRN: \(patientMRNText())")
        lines.append("DOB: \(patientDOBText())")
        lines.append("Sex: \(patientSexText())")
        lines.append("")
        lines.append("Physician: \(physicianNameText())")
        lines.append("Clinic: \(clinicNameText())")
        lines.append("Phone: \(physicianPhoneText())")
        lines.append("")
        if isBlankNote, !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Title: \(titleText)")
            lines.append("")
        }
        lines.append(normalizeForPrint(bodyText))
        return lines.joined(separator: "\n")
    }
    
    private func normalizeForPrint(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\r\n", with: "\n")
        // Convert ANY run of blank lines to a single newline (true single-spacing)
        return t.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
    }


#if canImport(UIKit)
private func printNote() {

    // 1) Get plain text (already includes normalizeForPrint(bodyText) if you added it)
    let text = exportText()

    // 2) Escape HTML
    var s = text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")

    // 3) Convert NEWLINES to <br/> (this is the key change vs <pre>)
    s = s.replacingOccurrences(of: "\n", with: "<br/>")

    // 4) Optional: make heading-only lines bold + slightly bigger
    // Matches lines like: "SUBJECTIVE:" / "PHYSICAL EXAMINATION:" etc.
    // (Works after newline-><br/> because the line breaks are now <br/>)
    s = s.replacingOccurrences(
        of: "(?m)(^|<br/>)([A-Z /&()\\-]{3,}:)(<br/>|$)",
        with: "$1<span style='font-weight:700; font-size:15px;'>$2</span>$3",
        options: .regularExpression
    )

    // 5) Wrap in HTML with controlled line-height (single spaced)
    let html = """
    <html>
    <body style="font-family: -apple-system; font-size: 12px; line-height: 1.15;">
    \(s)
    </body>
    </html>
    """

    let htmlString = exportHTMLForPrint()
    let formatter = UIMarkupTextPrintFormatter(markupText: htmlString)

    let controller = UIPrintInteractionController.shared
    controller.printFormatter = formatter
    controller.printInfo = {
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = "Medical Note"
        info.outputType = .general
        return info
    }()

    controller.present(animated: true, completionHandler: nil)
}
#else
private func printNote() { }
#endif

    // MARK: - Load / Save
    private func loadFromStoreIfNeeded() {
        guard !hasLoaded else { return }
        guard let n = currentNote else { return }

        titleText = n.title ?? ""
        bodyText  = n.body
        hasLoaded = true
    }

    private func scheduleAutoSave() {
        autoSaveWorkItem?.cancel()
        let work = DispatchWorkItem { saveDraftNow() }
        autoSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func saveDraftNow() {
        guard let idx = noteIndex else { return }
        guard !store.notes[idx].isFinalized else { return }

        var n = store.notes[idx]
        if isBlankNote { n.title = titleText }
        n.body = bodyText
        n.updatedAt = Date()

        store.notes[idx] = n
        store.saveNotes()
    }

    // MARK: - Formatting
    private func formatDateTime(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatDateOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - Patient helpers
    private func patientDisplayNameText() -> String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }

        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ar.isEmpty { return ar }

        return "—"
    }

    private func patientDOBText() -> String {
        formatDateOnly(patient.dob)
    }

    private func patientMRNText() -> String {
        let s = patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s
    }

    private func patientPhoneText() -> String {
        let s = patient.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s
    }

    private func patientSexText() -> String {
        // TODO: wire to your model (patient.gender or patient.sex).
        // Examples:
        // return patient.gender.rawValue
        // return patient.sex.rawValue
        return "—"
    }

    // MARK: - Physician helpers
    private func physicianNameText() -> String {
        if let id = physicians.selectedPhysicianID,
           let p = physicians.physicians.first(where: { $0.id == id }) {
            let s = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return "—"
    }

    private func clinicNameText() -> String {
        if let id = physicians.selectedPhysicianID,
           let p = physicians.physicians.first(where: { $0.id == id }) {

            let clinic = p.clinic.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clinic.isEmpty { return clinic }

            let spec = p.specialty.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spec.isEmpty { return spec }
        }

        let s = store.clinicName.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "—" : s
    }

    private func physicianPhoneText() -> String {
        if let id = physicians.selectedPhysicianID,
           let p = physicians.physicians.first(where: { $0.id == id }) {
            let s = p.contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return "—"
    }
}
