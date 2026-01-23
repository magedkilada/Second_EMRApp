import Foundation

enum SmartVitalsAdapter {

    // Try common field names WITHOUT hardcoding your model.
    private static let dateKeys = ["date", "timestamp", "time", "createdAt", "recordedAt", "measuredAt"]

    // Common weight keys
    private static let weightKeys = ["weightKg", "weight_kg", "weight", "wtKg", "wt"]

    // Common height keys
    private static let heightKeys = ["heightCm", "height_cm", "height", "htCm", "lengthCm", "length_cm", "length"]

    // Common head circumference keys
    private static let headKeys = ["headCircCm", "headCirc", "hcCm", "hc", "ofcCm", "ofc", "headCircumferenceCm", "headCircumference"]

    static func extractDate(from entry: SmartVitalsEntry) -> Date? {
        mirrorValue(entry, keys: dateKeys, as: Date.self)
    }

    static func extractValue(from entry: SmartVitalsEntry, metric: GrowthMetric) -> Double? {
        switch metric {
        case .weightForAge:
            return mirrorNumber(entry, keys: weightKeys)
        case .heightForAge:
            return mirrorNumber(entry, keys: heightKeys)
        case .headCircForAge:
            return mirrorNumber(entry, keys: headKeys)
        }
    }

    // MARK: - Mirror helpers

    private static func mirrorNumber(_ entry: Any, keys: [String]) -> Double? {
        // Accept Double, Int, Float, NSNumber, String convertible
        if let d: Double = mirrorValue(entry, keys: keys, as: Double.self) { return d }
        if let i: Int = mirrorValue(entry, keys: keys, as: Int.self) { return Double(i) }
        if let f: Float = mirrorValue(entry, keys: keys, as: Float.self) { return Double(f) }
        if let n: NSNumber = mirrorValue(entry, keys: keys, as: NSNumber.self) { return n.doubleValue }
        if let s: String = mirrorValue(entry, keys: keys, as: String.self) {
            return Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func mirrorValue<T>(_ entry: Any, keys: [String], as: T.Type) -> T? {
        // Search shallow
        let m = Mirror(reflecting: entry)
        for child in m.children {
            guard let label = child.label else { continue }
            if keys.contains(label) {
                return child.value as? T
            }
        }
        // Search one level deep (common if entry has nested "measurements" or "values")
        for child in m.children {
            let m2 = Mirror(reflecting: child.value)
            for c2 in m2.children {
                guard let label2 = c2.label else { continue }
                if keys.contains(label2) {
                    return c2.value as? T
                }
            }
        }
        return nil
    }
}
