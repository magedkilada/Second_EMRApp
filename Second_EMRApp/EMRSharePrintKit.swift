import SwiftUI
import UIKit
import CoreText

// MARK: - Top-most UIViewController helper

extension UIApplication {

    var emrTopMostViewController: UIViewController? {
        guard
            let scene = connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let window = scene.windows.first(where: { $0.isKeyWindow }),
            var top = window.rootViewController
        else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    var emrTopMostView: UIView? {
        emrTopMostViewController?.view
    }
}

// MARK: - Share sheet (iPad-safe)

struct EMRShareSheetView: UIViewControllerRepresentable {

    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes

        if let pop = vc.popoverPresentationController {
            let anchorView = UIApplication.shared.emrTopMostView ?? UIView()
            pop.sourceView = anchorView
            pop.sourceRect = CGRect(
                x: anchorView.bounds.midX,
                y: anchorView.bounds.maxY - 80,
                width: 1,
                height: 1
            )
            pop.permittedArrowDirections = []
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Print helpers

enum EMRPrintHelper {

    static func printFile(_ url: URL, jobName: String, onPresented: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = jobName

            controller.printInfo = info
            controller.printingItem = url

            guard let topVC = UIApplication.shared.emrTopMostViewController,
                  let anchorView = topVC.view
            else {
                controller.present(animated: true) { _, _, _ in onPresented?() }
                return
            }

            let rect = CGRect(
                x: anchorView.bounds.midX,
                y: anchorView.bounds.maxY - 80,
                width: 1,
                height: 1
            )

            controller.present(from: rect, in: anchorView, animated: true) { _, _, _ in
                onPresented?()
            }
        }
    }

    static func printTextAsPDF(_ text: String, title: String, jobName: String, onPresented: (() -> Void)? = nil) {
        guard let pdfURL = EMRSharePrintBuilder.makePDFFile(
            filename: safeFilename(jobName),
            title: title,
            body: text
        ) else { return }

        printFile(pdfURL, jobName: jobName, onPresented: onPresented)
    }

    private static func safeFilename(_ s: String) -> String {
        let allowed = s.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        return String(allowed.prefix(50))
    }
}

// MARK: - Builders

enum EMRSharePrintBuilder {

    static func makePDFFile(filename: String, title: String, body: String) -> URL? {
        let pdfData = renderPagedPDF(title: title, body: body)
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

    // ✅ Multi-page PDF renderer using CoreText pagination
    private static func renderPagedPDF(title: String, body: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter @ 72dpi
        let margin: CGFloat = 36

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let bodyFont  = UIFont.systemFont(ofSize: 12)

        let combined = NSMutableAttributedString()

        combined.append(NSAttributedString(
            string: title + "\n\n",
            attributes: [.font: titleFont]
        ))

        combined.append(NSAttributedString(
            string: body,
            attributes: [.font: bodyFont]
        ))

        let framesetter = CTFramesetterCreateWithAttributedString(combined as CFAttributedString)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            var currentRange = CFRange(location: 0, length: 0)

            while currentRange.location < combined.length {
                ctx.beginPage()

                let context = ctx.cgContext
                context.saveGState()

                // Flip coordinate system for CoreText
                context.translateBy(x: 0, y: pageRect.height)
                context.scaleBy(x: 1.0, y: -1.0)

                let textRect = CGRect(
                    x: margin,
                    y: margin,
                    width: pageRect.width - margin * 2,
                    height: pageRect.height - margin * 2
                )

                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

                CTFrameDraw(frame, context)

                // Advance range
                let visible = CTFrameGetVisibleStringRange(frame)
                currentRange = CFRange(location: currentRange.location + visible.length, length: 0)

                context.restoreGState()
            }
        }
    }
}








