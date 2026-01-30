//
//  QuickLookPreview.swift
//  Second_EMRApp
//

import SwiftUI
import QuickLook

#if os(iOS)
/// SwiftUI wrapper for iOS QuickLook preview.
struct QuickLookPreview: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

#elseif os(macOS)
/// macOS QuickLook placeholder — opens the file with the system viewer.
struct QuickLookPreview: View {
    let url: URL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.headline)
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
#endif
