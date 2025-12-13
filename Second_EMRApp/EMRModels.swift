import Foundation

public struct Patient: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()

    // Demographics
    public var nameEnglish: String = ""
    public var nameArabic: String = ""
    public var dob: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    public var phone: String = ""
    public var mrn: String = ""
    public var nationalID: String = ""
    public var passport: String = ""
    public var email: String = ""

    // Soft delete (optional but handy later)
    public var isDeleted: Bool = false

    public init() {}
}

// MARK: - Validation / Sanitizers

public enum EMRValidation {
    /// Keep only + and digits. Ensure + only appears at the start.
    public static func sanitizePhone(_ input: String) -> String {
        let allowed = input.filter { $0.isNumber || $0 == "+" }
        // Collapse extra '+' and ensure if present it's first
        var result = allowed.replacingOccurrences(of: "++", with: "+")
        let plusCount = result.filter { $0 == "+" }.count
        if plusCount > 1 {
            // remove all '+' then add one at start
            result = result.filter { $0 != "+" }
            result = "+" + result
        } else if plusCount == 1, !result.hasPrefix("+") {
            result = result.filter { $0 != "+" }
            result = "+" + result
        }
        return result
    }

    /// Digits only (MRN / National ID)
    public static func digitsOnly(_ input: String) -> String {
        input.filter { $0.isNumber }
    }

    /// Passport: uppercase letters and digits only
    public static func sanitizePassport(_ input: String) -> String {
        input.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
    }

    /// Very light email cleanup (you can tighten later)
    public static func sanitizeEmail(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// DOB cannot be in the future
    public static func clampDOB(_ date: Date) -> Date {
        min(date, Date())
    }
}
