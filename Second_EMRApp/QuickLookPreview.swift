//
//  QuickLookPreview.swift
//  Second_EMRApp
//

import SwiftUI
import QuickLook
import PDFKit

// MARK: - PDFKitView (used by ReferencesView and others)

#if os(iOS)
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}
#elseif os(macOS)
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}
#endif

// MARK: - QuickLookPreview (universal file preview using system QL)

#if os(iOS)
/// Uses the system QLPreviewController — handles PDFs, images, EEG files, and many more.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#elseif os(macOS)

/// macOS: handles PDFs via PDFKit and images via NSImage for reliable sheet presentation.
/// Falls back to a simple text message for unsupported file types.
struct QuickLookPreview: View {
    let url: URL

    var body: some View {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            PDFKitView(url: url)
        } else if ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"].contains(ext) {
            MacImagePreview(url: url)
        } else {
            // Generic file — show icon + name + open-in-Finder button
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.title3).bold()
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MacImagePreview: View {
    let url: URL

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            let img = Image(nsImage: nsImage)
            ScrollView([.horizontal, .vertical]) {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Unable to load image")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
