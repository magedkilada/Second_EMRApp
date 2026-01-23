import Foundation

// ✅ One place to map YOUR model field names to what the header needs.
struct HeaderPatientFields {
    var patientName: String
    var mrn: String
    var dob: Date?
    var sex: String
    var phone: String
    var clinic: String
}

struct HeaderNoteFields {
    var physician: String
    var createdAt: Date
    var updatedAt: Date
}

struct NoteHeaderBuilder {

    static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    static func headerText(patient: HeaderPatientFields, note: HeaderNoteFields) -> String {
        var lines: [String] = []

        // ✅ Order you requested
        lines.append("Patient: \(patient.patientName)")
        if !patient.mrn.isEmpty { lines.append("MRN: \(patient.mrn)") }

        if let dob = patient.dob {
            let dobF = DateFormatter()
            dobF.dateStyle = .medium
            dobF.timeStyle = .none
            lines.append("DOB: \(dobF.string(from: dob))")
        } else {
            lines.append("DOB: —")
        }

        lines.append("Sex: \(patient.sex.isEmpty ? "—" : patient.sex)")
        lines.append("Clinic: \(patient.clinic.isEmpty ? "—" : patient.clinic)")
        lines.append("Physician: \(note.physician.isEmpty ? "—" : note.physician)")
        lines.append("Note created: \(formatDate(note.createdAt))")
        lines.append("Note updated: \(formatDate(note.updatedAt))")

        return lines.joined(separator: "\n")
    }
}
