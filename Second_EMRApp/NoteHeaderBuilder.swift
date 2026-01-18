import Foundation
import SwiftUI

struct NoteHeaderBuilder {

    private static func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private static func formatDOB(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    // ✅ Attributed header (lets us BOLD specific lines)
    static func headerAttributed(
        createdAt: Date,
        updatedAt: Date,

        physicianName: String,
        clinicName: String,
        physicianPhone: String,

        patientName: String,
        mrn: String,
        dob: Date?,
        sex: String,
        patientPhone: String
    ) -> AttributedString {

        var out = AttributedString()

        func appendLine(_ s: String, bold: Bool = false) {
            var a = AttributedString(s + "\n")
            if bold { a.font = .system(.footnote, design: .default).bold() }
            out += a
        }

        // ✅ Top: created/updated (requested)
        appendLine("Created: \(formatDateTime(createdAt))")
        appendLine("Updated: \(formatDateTime(updatedAt))")
        appendLine("") // blank line

        // ✅ Physician / clinic block (BOLD) — order you requested
        appendLine(physicianName.isEmpty ? "Physician: —" : physicianName, bold: true)
        appendLine(clinicName.isEmpty ? "Clinic: —" : clinicName, bold: true)
        if !physicianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLine("Tel: \(physicianPhone)", bold: true)
        } else {
            appendLine("Tel: —", bold: true)
        }

        appendLine("") // blank line

        // ✅ Patient block (BOLD) — demographics EXCLUDING nationalID/passport
        appendLine(patientName.isEmpty ? "Patient: —" : patientName, bold: true)

        appendLine("MRN: \(mrn.isEmpty ? "—" : mrn)", bold: true)
        appendLine("DOB: \(formatDOB(dob))", bold: true)
        appendLine("Sex: \(sex.isEmpty ? "—" : sex)", bold: true)
        appendLine("Phone: \(patientPhone.isEmpty ? "—" : patientPhone)", bold: true)

        return out
    }
}
