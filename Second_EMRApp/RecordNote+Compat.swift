import Foundation

extension RecordNote {
    /// Compatibility shim for older UI code that used `title`.
    /// We map it to your current `displayTitle`.
    var title: String { displayTitle }
}
