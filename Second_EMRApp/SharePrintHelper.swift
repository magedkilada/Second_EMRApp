import SwiftUI
import PDFKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Direct Presenters (platform-specific)

enum SharePrintPresenter {

    #if os(iOS)
    static func share(items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow),
              let rootVC = window.rootViewController else { return }

        var top = rootVC
        while let presented = top.presentedViewController { top = presented }

        let presentShare = { (presenter: UIViewController) in
            let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = presenter.view
                pop.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            presenter.present(vc, animated: true)
        }

        if top !== rootVC {
            top.dismiss(animated: false) {
                var newTop = rootVC
                while let presented = newTop.presentedViewController { newTop = presented }
                presentShare(newTop)
            }
        } else {
            presentShare(top)
        }
    }

    static func printURL(_ url: URL, jobName: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow),
              let rootVC = window.rootViewController else { return }

        var top = rootVC
        while let presented = top.presentedViewController { top = presented }

        let doPrint = {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = jobName
            info.outputType = .general
            controller.printInfo = info
            controller.printingItem = url
            controller.present(animated: true)
        }

        if top !== rootVC {
            top.dismiss(animated: false) { doPrint() }
        } else {
            doPrint()
        }
    }

    #elseif os(macOS)
    static func share(items: [Any]) {
        guard let url = items.compactMap({ $0 as? URL }).first else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow, let contentView = window.contentView {
            let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
        }
    }

    static func printURL(_ url: URL, jobName: String) {
        let printOp: NSPrintOperation?
        if url.pathExtension.lowercased() == "pdf", let pdfDoc = PDFDocument(url: url) {
            printOp = pdfDoc.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        } else if let text = try? String(contentsOf: url, encoding: .utf8) {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            tv.string = text
            printOp = NSPrintOperation(view: tv)
        } else {
            return
        }
        guard let op = printOp else { return }
        op.jobTitle = jobName
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // Use the first visible window — NSApp.keyWindow can be nil in SwiftUI
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }
    #endif
}

// MARK: - File Builders (Text -> TXT, Text -> PDF)

enum SharePrintBuilder {

    static func makeTXTFile(filename: String, text: String) -> URL? {
        let safe = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension("txt")
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func makePDFFile(filename: String, title: String, body: String) -> URL? {
        let safe = filename.replacingOccurrences(of: "/", with: "-")
        let pdfData = renderMultiPagePDF(body: body)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
            .appendingPathExtension("pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Multi-page PDF renderer

    private static func renderMultiPagePDF(body: String) -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 54
        let contentWidth = pageWidth - margin * 2
        let contentHeight = pageHeight - margin * 2
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3

        #if os(iOS)
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let bodyFont = UIFont.systemFont(ofSize: 11)
        let separatorFont = UIFont.systemFont(ofSize: 6)
        let grayColor: Any = UIColor.gray
        #elseif os(macOS)
        let headerFont = NSFont.boldSystemFont(ofSize: 10)
        let bodyFont = NSFont.systemFont(ofSize: 11)
        let separatorFont = NSFont.systemFont(ofSize: 6)
        let grayColor: Any = NSColor.gray
        #endif

        let separator = String(repeating: "\u{2500}", count: 56)
        let parts = body.components(separatedBy: separator)

        let fullAttr = NSMutableAttributedString()

        if parts.count >= 2 {
            let headerText = parts[0]
            fullAttr.append(NSAttributedString(
                string: headerText,
                attributes: [.font: headerFont, .paragraphStyle: style]
            ))
            fullAttr.append(NSAttributedString(
                string: String(repeating: "\u{2500}", count: 72) + "\n",
                attributes: [.font: separatorFont, .foregroundColor: grayColor]
            ))
            let bodyText = parts.dropFirst().joined(separator: separator)
            fullAttr.append(NSAttributedString(
                string: bodyText,
                attributes: [.font: bodyFont, .paragraphStyle: style]
            ))
        } else {
            fullAttr.append(NSAttributedString(
                string: body,
                attributes: [.font: bodyFont, .paragraphStyle: style]
            ))
        }

        let storage = NSTextStorage(attributedString: fullAttr)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        #if os(iOS)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            var done = false
            let totalGlyphs = layoutManager.numberOfGlyphs

            while !done {
                let textContainer = NSTextContainer(size: CGSize(width: contentWidth, height: contentHeight))
                textContainer.lineFragmentPadding = 0
                layoutManager.addTextContainer(textContainer)

                ctx.beginPage()

                let glyphRange = layoutManager.glyphRange(for: textContainer)

                if glyphRange.length == 0 {
                    done = true
                } else {
                    let origin = CGPoint(x: margin, y: margin)
                    layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
                    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)

                    if NSMaxRange(glyphRange) >= totalGlyphs {
                        done = true
                    }
                }
            }
        }
        #elseif os(macOS)
        let pdfData = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        var done = false
        let totalGlyphs = layoutManager.numberOfGlyphs

        while !done {
            let textContainer = NSTextContainer(size: CGSize(width: contentWidth, height: contentHeight))
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)

            cgContext.beginPDFPage(nil)

            let glyphRange = layoutManager.glyphRange(for: textContainer)

            if glyphRange.length == 0 {
                done = true
            } else {
                let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: false)
                NSGraphicsContext.current = nsContext
                let origin = CGPoint(x: margin, y: margin)
                layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
                layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)

                if NSMaxRange(glyphRange) >= totalGlyphs {
                    done = true
                }
            }

            cgContext.endPDFPage()
        }

        cgContext.closePDF()
        return pdfData as Data
        #endif
    }
}
