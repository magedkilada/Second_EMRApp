import Foundation

public enum EMRValidation {
    public static func digitsOnly(_ s: String) -> String {
        s.filter { $0.isNumber }
    }

    // Phone: allow leading + then digits only
    public static func sanitizePhone(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        var out = ""
        for (i, ch) in trimmed.enumerated() {
            if i == 0 && ch == "+" { out.append(ch) }
            else if ch.isNumber { out.append(ch) }
        }
        return out
    }

    // Passport: CAPS + digits only
    public static func sanitizePassport(_ s: String) -> String {
        let upper = s.uppercased()
        return upper.filter { $0.isNumber || ("A"..."Z").contains($0) }
    }

    public static func sanitizeEmail(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // No future DOB
    public static func clampDOB(_ d: Date) -> Date {
        min(d, Date())
    }
}
