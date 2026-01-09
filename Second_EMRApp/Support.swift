import SwiftUI
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
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text {
            tv.text = text
        }

        // keep selection in sync (only if it differs)
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

/// Inserts `insert` at the current cursor/selection.
func insertAtCursor(text: inout String, range: inout NSRange, insert: String) {
    guard let swiftRange = Range(range, in: text) else {
        text += insert
        range = NSRange(location: (text as NSString).length, length: 0)
        return
    }

    text.replaceSubrange(swiftRange, with: insert)

    // Move cursor to end of inserted text
    let newLoc = (text as NSString).lengthOfBytes(using: String.Encoding.utf16.rawValue)
    // Safer: compute using NSString lengths
    let ns = text as NSString
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
import Foundation

extension Date {
    /// Full years elapsed from this date until now
    var ageYears: Int {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year], from: self, to: now)
        return max(0, comps.year ?? 0)
    }
}

