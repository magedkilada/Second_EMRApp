// MARK: - Batch Print Mode

enum BatchPrintMode: String, CaseIterable, Identifiable {
    case allNotes
    case prescriptionsOnly
    case notesAndPrescriptions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allNotes:
            return "All Notes"
        case .prescriptionsOnly:
            return "Prescriptions Only"
        case .notesAndPrescriptions:
            return "Notes + Prescriptions"
        }
    }
}

