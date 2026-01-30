//
//  NoteHeaderBuilder.swift
//  Second_EMRApp
//
//  Compact header for printed / shared notes.
//  Includes: patient name, MRN, DOB, gender, phone
//            physician name, clinic, phone, email
//  Excludes: passport, national ID

import Foundation

struct NoteHeaderBuilder {

    /// Compact header for print & share — fits ~6 lines at the top of the page.
    static func compactHeader(
        note: RecordNote,
        patient: Patient,
        physicianName: String,
        clinicName: String,
        physicianPhone: String?,
        physicianEmail: String?
    ) -> String {

        let dob = patient.dob.formatted(date: .abbreviated, time: .omitted)
        let age = patient.ageString ?? "—"
        let date = note.updatedAt.formatted(date: .abbreviated, time: .shortened)

        // Line 1: Note type + date
        var lines: [String] = []
        lines.append("\(note.displayTitle.uppercased())  —  \(date)")

        // Line 2: Patient info (name | MRN | DOB/Age | Gender)
        var patientParts: [String] = []
        patientParts.append(patient.nameEnglish)
        if !patient.mrn.isEmpty { patientParts.append("MRN: \(patient.mrn)") }
        patientParts.append("DOB: \(dob) (\(age))")
        patientParts.append(patient.gender.rawValue)
        lines.append(patientParts.joined(separator: "  |  "))

        // Line 3: Patient phone (if present)
        if !patient.phone.isEmpty {
            lines.append("Phone: \(patient.phone)")
        }

        // Line 4: Physician info
        var physicianParts: [String] = []
        physicianParts.append("Dr. \(physicianName)")
        if !clinicName.isEmpty { physicianParts.append(clinicName) }
        if let ph = physicianPhone, !ph.isEmpty { physicianParts.append(ph) }
        if let em = physicianEmail, !em.isEmpty { physicianParts.append(em) }
        lines.append(physicianParts.joined(separator: "  |  "))

        // Separator
        lines.append(String(repeating: "\u{2500}", count: 56))
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
