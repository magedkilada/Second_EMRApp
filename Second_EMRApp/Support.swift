import SwiftUI

#if os(iOS)
import UIKit

/// A plain UITextView wrapped for SwiftUI that exposes the cursor/selection (selectedRange).
struct CursorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isEditable: Bool
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = font
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        tv.delegate = context.coordinator
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.isEditable = isEditable
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }
        tv.isEditable = isEditable
        if tv.selectedRange.location != selectedRange.location || tv.selectedRange.length != selectedRange.length {
            tv.selectedRange = selectedRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text ?? ""
            selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange = textView.selectedRange
        }
    }
}

#elseif os(macOS)
import AppKit

/// A plain NSTextView wrapped for SwiftUI that exposes the cursor/selection (selectedRange).
struct CursorTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let isEditable: Bool
    var font: NSFont = .preferredFont(forTextStyle: .body)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.font = font
        tv.isEditable = isEditable
        tv.isRichText = false
        tv.allowsUndo = true
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 10, height: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        tv.isEditable = isEditable
        let current = tv.selectedRange()
        if current.location != selectedRange.location || current.length != selectedRange.length {
            tv.setSelectedRange(selectedRange)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            selectedRange = tv.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            selectedRange = tv.selectedRange()
        }
    }
}
#endif

/// Inserts `insert` at the current cursor/selection.
func insertAtCursor(text: inout String, range: inout NSRange, insert: String) {
    guard let swiftRange = Range(range, in: text) else {
        text += insert
        range = NSRange(location: (text as NSString).length, length: 0)
        return
    }

    text.replaceSubrange(swiftRange, with: insert)

    let insertedLen = (insert as NSString).length
    let startLoc = range.location
    range = NSRange(location: startLoc + insertedLen, length: 0)
}

struct NoteHeaderCard: View {
    let headerText: String

    var body: some View {
        GroupBox {
            Text(headerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
