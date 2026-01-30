#if os(iOS)
import UIKit

struct BatchNoteExporter {

    static func printNotes(_ notes: [RecordNote], patient: Patient) {
        let combinedText = notes
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
            .map { note in
                """
                \(note.displayTitle)
                Created: \(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                Updated: \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))

                \(note.body)

                ----------------------------------------
                """
            }
            .joined(separator: "\n\n")

        let formatter = UISimpleTextPrintFormatter(text: combinedText)
        formatter.perPageContentInsets = UIEdgeInsets(top: 72, left: 54, bottom: 72, right: 54)

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "\(patient.nameEnglish) – Notes"
        printInfo.outputType = .general

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printFormatter = formatter
        controller.present(animated: true)
    }
}
#endif
