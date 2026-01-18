//
//  EMRPrintHelper.swift
//  Second_EMRApp
//

import Foundation

#if canImport(UIKit)
import UIKit

@MainActor
enum EMRPrintHelper {

    /// Build a PDF from plain text and print it.
    /// Calls `onPresented` AFTER the print UI is presented (so sheets can dismiss cleanly).
    static func printTextAsPDF(
        _ text: String,
        title: String,
        jobName: String,
        onPresented: (() -> Void)? = nil
    ) {
        do {
            let url = try buildPDF(from: text, filename: "\(safeFileName(jobName)).pdf", title: title)
            printPDF(at: url, jobName: jobName, onPresented: onPresented)
        } catch {
            // If you want, wire this to store.lastErrorMessage at call site
            print("EMRPrintHelper error: \(error)")
        }
    }

    /// Print an existing PDF file URL.
    static func printPDF(
        at url: URL,
        jobName: String,
        onPresented: (() -> Void)? = nil
    ) {
        let controller = UIPrintInteractionController.shared

        let info = UIPrintInfo(dictionary: nil)
        info.jobName = jobName
        info.outputType = .general
        controller.printInfo = info

        controller.printingItem = url

        controller.present(animated: true) { _, completed, error in
            if let error { print("Print error: \(error)") }
            // Dismiss sheets after UI is presented (or after completion — either is fine)
            onPresented?()
            _ = completed
        }
    }

    // MARK: - PDF builder (multi-page)

    private static func buildPDF(from text: String, filename: String, title: String) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let margin: CGFloat = 36
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: title
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { ctx in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraph
            ]

            let attributed = NSAttributedString(string: text, attributes: attrs)

            // Use a text formatter that paginates properly
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            var currentRange = CFRange(location: 0, length: 0)

            while currentRange.location < attributed.length {
                ctx.beginPage()

                let path = CGPath(rect: contentRect, transform: nil)

                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    currentRange,
                    path,
                    nil
                )

                let context = ctx.cgContext
                context.saveGState()

                // Flip coordinate system for CoreText
                context.translateBy(x: 0, y: pageRect.height)
                context.scaleBy(x: 1.0, y: -1.0)

                CTFrameDraw(frame, context)

                context.restoreGState()

                // Advance range
                let visible = CTFrameGetVisibleStringRange(frame)
                currentRange.location += visible.length
                currentRange.length = 0
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined(separator: "_")
    }
}

#else

@MainActor
enum EMRPrintHelper {
    static func printTextAsPDF(_ text: String, title: String, jobName: String, onPresented: (() -> Void)? = nil) { }
    static func printPDF(at url: URL, jobName: String, onPresented: (() -> Void)? = nil) { }
}

#endif
