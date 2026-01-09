import SwiftUI
import UIKit

enum PrintShareHelper {

    // MARK: - Share

    static func shareText(_ text: String, title: String = "Medical Record") {
        let vc = UIActivityViewController(activityItems: [title, text], applicationActivities: nil)
        present(vc)
    }

    static func shareURL(_ url: URL, title: String = "Attachment") {
        let vc = UIActivityViewController(activityItems: [title, url], applicationActivities: nil)
        present(vc)
    }

    // MARK: - Print

    static func printText(_ text: String, jobName: String = "Medical Record") {
        let pc = UIPrintInteractionController.shared
        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.startPage = 0
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        formatter.maximumContentWidth = 500

        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName

        pc.printInfo = info
        pc.printFormatter = formatter
        pc.present(animated: true, completionHandler: nil)
    }

    static func printFile(_ url: URL, jobName: String = "Attachment") {
        let pc = UIPrintInteractionController.shared

        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName

        pc.printInfo = info
        pc.printingItem = url
        pc.present(animated: true, completionHandler: nil)
    }

    // MARK: - Presenter

    private static func present(_ vc: UIViewController) {
        guard let top = UIApplication.shared.topMostViewController else { return }
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX,
                                                             y: top.view.bounds.midY,
                                                             width: 1, height: 1)
        top.present(vc, animated: true)
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let scene = connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
