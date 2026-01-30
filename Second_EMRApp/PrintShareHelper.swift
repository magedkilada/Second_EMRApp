#if os(iOS)
import SwiftUI
import UIKit

enum PrintShareHelper {

    // MARK: Share

    static func shareText(_ text: String, title: String = "Medical Record") {
        let vc = UIActivityViewController(activityItems: [title, text], applicationActivities: nil)
        present(vc)
    }

    // MARK: Print

    static func printText(_ text: String, jobName: String = "Medical Record") {
        let printController = UIPrintInteractionController.shared
        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.startPage = 0
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        formatter.maximumContentWidth = 500

        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        printController.printInfo = info
        printController.printFormatter = formatter

        printController.present(animated: true, completionHandler: nil)
    }

    // MARK: - Presenter

    private static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
}
#endif
