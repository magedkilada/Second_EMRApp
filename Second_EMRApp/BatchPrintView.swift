import SwiftUI

struct BatchPrintView: View {

    // MARK: - Inputs
    let patient: Patient

    /// Optional header info (pass from NoteEditorView or RecordsWorkspaceView)
    let clinicName: String
    let physicianName: String
    let physicianSpecialty: String

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Selection
    @State private var selectedNotes: Set<UUID> = []
    @State private var selectedAttachments: Set<UUID> = []

    // MARK: - Init
    init(
        patient: Patient,
        clinicName: String = "",
        physicianName: String = "",
        physicianSpecialty: String = ""
    ) {
        self.patient = patient
        self.clinicName = clinicName
        self.physicianName = physicianName
        self.physicianSpecialty = physicianSpecialty
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Header (shows on screen; coordinator should include in print header too)
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(patientDisplayName)
                            .font(.headline)

                        Text("MRN: \(patient.mrn.isEmpty ? "—" : patient.mrn)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !clinicNameTrimmed.isEmpty || !physicianNameTrimmed.isEmpty || !physicianSpecialtyTrimmed.isEmpty {
                            Divider().padding(.vertical, 6)

                            if !clinicNameTrimmed.isEmpty {
                                Text(clinicNameTrimmed)
                                    .font(.subheadline)
                            }
                            if !physicianNameTrimmed.isEmpty {
                                Text(physicianNameTrimmed)
                                    .font(.subheadline)
                            }
                            if !physicianSpecialtyTrimmed.isEmpty {
                                Text(physicianSpecialtyTrimmed)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Header")
                }

                // MARK: Notes & Prescriptions (single list, as you had)
                Section {
                    HStack(spacing: 12) {
                        Button("Select All") { selectAllNotes() }
                        Button("Clear") { selectedNotes.removeAll() }
                        Spacer()
                        Text("\(selectedNotes.count)/\(patientNotes.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)

                    ForEach(patientNotes) { note in
                        MultipleSelectionRow(
                            title: note.displayTitle,
                            subtitle: note.type.rawValue,
                            isSelected: selectedNotes.contains(note.id)
                        ) {
                            toggle(note.id, in: &selectedNotes)
                        }
                    }
                } header: {
                    Text("Notes & Prescriptions")
                }

                // MARK: Attachments
                Section {
                    HStack(spacing: 12) {
                        Button("Select All") { selectAllAttachments() }
                        Button("Clear") { selectedAttachments.removeAll() }
                        Spacer()
                        Text("\(selectedAttachments.count)/\(patientAttachments.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)

                    ForEach(patientAttachments) { att in
                        MultipleSelectionRow(
                            title: att.originalFileName,
                            subtitle: att.category.rawValue,
                            isSelected: selectedAttachments.contains(att.id)
                        ) {
                            toggle(att.id, in: &selectedAttachments)
                        }
                    }
                } header: {
                    Text("Attachments")
                }
            }
            .navigationTitle("Batch Print")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        BatchPrintCoordinator.print(
                            patient: patient,
                            notes: selectedNotes,
                            attachments: selectedAttachments,
                            store: store
                        )
                        dismiss()
                    }
                    .disabled(selectedNotes.isEmpty && selectedAttachments.isEmpty)
                }
            }
        }
    }

    // MARK: - Data

    private var patientNotes: [RecordNote] {
        store.notes
            .filter { $0.patientID == patient.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var patientAttachments: [Attachment] {
        store.attachments
            .filter { $0.patientID == patient.id }
            .sorted { $0.originalFileName.localizedCaseInsensitiveCompare($1.originalFileName) == .orderedAscending }
    }

    // MARK: - Helpers

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
    }

    private func selectAllNotes() {
        selectedNotes = Set(patientNotes.map { $0.id })
    }

    private func selectAllAttachments() {
        selectedAttachments = Set(patientAttachments.map { $0.id })
    }

    private var patientDisplayName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Patient"
    }

    private var clinicNameTrimmed: String {
        clinicName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var physicianNameTrimmed: String {
        physicianName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var physicianSpecialtyTrimmed: String {
        physicianSpecialty.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}// MARK: - MultipleSelectionRow (helper)

private struct MultipleSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BatchPrintCoordinator (minimal working)

enum BatchPrintCoordinator {

    /// Prints selected notes as TEXT and selected attachments as FILES (PDF/images/etc.).
    static func print(
        patient: Patient,
        notes: Set<UUID>,
        attachments: Set<UUID>,
        store: EMRStore
    ) {
        // 1) Notes -> one combined text print job
        let selectedNotes: [RecordNote] = store.notes
            .filter { $0.patientID == patient.id && notes.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }

        if !selectedNotes.isEmpty {
            let text = buildBatchText(patient: patient, notes: selectedNotes)
            PrintShareHelper.printText(text)   // uses your existing helper
        }

        // 2) Attachments -> print each file (PDF/image) as its own print job
        let selectedAttachments: [Attachment] = store.attachments
            .filter { $0.patientID == patient.id && attachments.contains($0.id) }

        for att in selectedAttachments {
            if let url = attachmentFileURL(att, store: store) {
                PrintShareHelper.printFile(url) // ✅ you need this helper; see note below
            }
        }
    }

    private static func buildBatchText(patient: Patient, notes: [RecordNote]) -> String {
        let nameEN = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameAR = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = !nameEN.isEmpty ? nameEN : (!nameAR.isEmpty ? nameAR : "Patient")

        var lines: [String] = []
        lines.append("=== \(name) ===")
        lines.append("MRN: \(patient.mrn.isEmpty ? "—" : patient.mrn)")
        lines.append("DOB: \(patient.dob.formatted(date: .abbreviated, time: .omitted))")
        lines.append("")

        for n in notes {
            lines.append("--------------------------------------------------")
            lines.append(n.displayTitle)
            lines.append(n.type.rawValue)
            lines.append("Updated: \(n.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            lines.append("")
            lines.append(n.body)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func attachmentFileURL(_ att: Attachment, store: EMRStore) -> URL? {
        // If your EMRStore already has a helper like attachmentFileURL(_:) use it instead.
        // Otherwise, this assumes your app stores attachments under Documents/EMR_Attachments/<patientID>/<category>/<storedFileName>
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }

        return docs
            .appendingPathComponent("EMR_Attachments", isDirectory: true)
            .appendingPathComponent(att.patientID.uuidString, isDirectory: true)
            .appendingPathComponent(att.category.rawValue, isDirectory: true)
            .appendingPathComponent(att.storedFileName, isDirectory: false)
    }
}


