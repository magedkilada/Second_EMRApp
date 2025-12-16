import Foundation
import UIKit

enum BatchPrescriptionExporter {

    /// Builds a PDF from plain text and returns the file URL.
    static func buildPDF(text: String, filename: String) throws -> URL {

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let margin: CGFloat = 36
        let textRect = pageRect.insetBy(dx: margin, dy: margin)

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraph
            ]

            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])

        return url
    }
}
