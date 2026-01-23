import SwiftUI
import UIKit
import PDFKit

// MARK: - Share Sheet (AirDrop / Files / Messages / Mail)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes

        // ✅ iPad: must set popover anchor, otherwise crash/blank weird behavior
        if let pop = vc.popoverPresentationController {
            pop.sourceView = UIApplication.shared.topMostViewController?.view
            pop.sourceRect = CGRect(x: UIScreen.main.bounds.midX,
                                    y: UIScreen.main.bounds.maxY - 80,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

import SwiftUI
import UIKit

// MARK: - Print Sheet (PDF / TXT)

struct PrintSheet: UIViewControllerRepresentable {
    let jobName: String
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()

        DispatchQueue.main.async {
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.jobName = jobName
            printInfo.outputType = .general

            let controller = UIPrintInteractionController.shared
            controller.printInfo = printInfo
            controller.printingItem = fileURL

            // ✅ iPad-safe presentation (NO popover access)
            controller.present(animated: true)
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

// MARK: - File Builders (Text -> TXT, Text -> PDF)

enum SharePrintBuilder {

    static func makeTXTFile(filename: String, text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("txt")
        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func makePDFFile(filename: String, title: String, body: String) -> URL? {
        let pdfData = renderSimplePDF(title: title, body: body)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("pdf")
        do {
            try pdfData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // Basic PDF renderer (fast, stable)
    private static func renderSimplePDF(title: String, body: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            ctx.beginPage()

            let margin: CGFloat = 36
            var y: CGFloat = margin

            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let bodyFont  = UIFont.systemFont(ofSize: 12)

            let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont]
            let bodyAttr:  [NSAttributedString.Key: Any] = [.font: bodyFont]

            let titleStr = NSAttributedString(string: title + "\n\n", attributes: titleAttr)
            let bodyStr  = NSAttributedString(string: body, attributes: bodyAttr)

            let titleSize = titleStr.boundingRect(
                with: CGSize(width: pageRect.width - margin*2, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            titleStr.draw(in: CGRect(x: margin, y: y, width: pageRect.width - margin*2, height: titleSize.height))
            y += titleSize.height

            let bodyRect = CGRect(x: margin, y: y, width: pageRect.width - margin*2, height: pageRect.height - y - margin)
            bodyStr.draw(with: bodyRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }
}

// MARK: - UIKit convenience: top view controller for popovers

private extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
