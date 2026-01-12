//
//  BatchPrintView.swift
//  Second_EMRApp
//
//  Batch printing for selected notes of ONE patient.
//  - Header includes: Physician + Clinic + Patient demographics (EXCLUDING Passport & National ID)
//  - Dismiss AFTER print is presented (prevents flash/disappear)
//

import SwiftUI

struct BatchPrintView: View {

    let patient: Patient

    @EnvironmentObject private var store: EMRStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedNoteIDs: Set<UUID> = []

    private var patientNotes: [RecordNote] {
        store.notes
            .filter { $0.patientID == patient.id && !$0.isDeleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(patientNotes) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.displayTitle).font(.headline)
                            Text(note.type.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: selectedNoteIDs.contains(note.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedNoteIDs.contains(note.id) ? .blue : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(note.id) }
                }
            }
            .navigationTitle("Batch Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Print \(selectedNoteIDs.count)") {
                        printSelectedAndDismiss()
                    }
                    .disabled(selectedNoteIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedNoteIDs.contains(id) { selectedNoteIDs.remove(id) }
        else { selectedNoteIDs.insert(id) }
    }

    // MARK: - Header (baseline truth)
    private func headerBlock() -> String {
        var lines: [String] = []

        let physician = store.treatingPhysicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clinic = store.clinicName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !physician.isEmpty { lines.append(physician) }
        if !clinic.isEmpty { lines.append(clinic) }

        lines.append("")

        // Patient demographics (EXCLUDE passport + national ID)
        lines.append("Patient: \(patientDisplayName())")

        let mrn = patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mrn.isEmpty { lines.append("MRN: \(mrn)") }

        let dob = patient.dob.formatted(date: .abbreviated, time: .omitted)
        lines.append("DOB: \(dob)")

        let phone = patient.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty { lines.append("Phone: \(phone)") }

        lines.append("Sex: \(patient.gender.rawValue)")

        lines.append("")
        lines.append(String(repeating: "=", count: 60))
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func patientDisplayName() -> String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        return !en.isEmpty ? en : (!ar.isEmpty ? ar : "Unnamed patient")
    }

    // MARK: - Print
    private func printSelectedAndDismiss() {
        let notesToPrint = patientNotes
            .filter { selectedNoteIDs.contains($0.id) }
            .sorted { $0.updatedAt < $1.updatedAt } // older → newer

        var combinedText = headerBlock()

        for (index, note) in notesToPrint.enumerated() {
            if index > 0 {
                combinedText += "\n\n" + String(repeating: "=", count: 60) + "\n\n"
            }

            combinedText += "\(note.displayTitle)\n"
            combinedText += "\(note.type.rawValue)\n"
            combinedText += "Updated: \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))\n\n"
            combinedText += note.body
        }

        EMRPrintHelper.printTextAsPDF(
            combinedText,
            title: "Batch Medical Records",
            jobName: "Batch Medical Records"
        ) {
            dismiss()
        }
    }
}
