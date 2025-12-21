import SwiftUI
import UIKit

/// A SwiftUI text view that exposes the current cursor/selection range,
/// so you can insert text exactly where the user clicked.


// MARK: - Helpers (insert at cursor)

extension String {
    /// Inserts `insertion` at `range` and returns the new string + the new cursor position.
    func inserting(_ insertion: String, at range: NSRange) -> (String, NSRange) {
        let ns = self as NSString
        let safeLocation = max(0, min(range.location, ns.length))
        let safeLength = max(0, min(range.length, ns.length - safeLocation))
        let safeRange = NSRange(location: safeLocation, length: safeLength)

        let newText = ns.replacingCharacters(in: safeRange, with: insertion)
        let newCursor = NSRange(location: safeLocation + (insertion as NSString).length, length: 0)
        return (newText, newCursor)
    }
}
