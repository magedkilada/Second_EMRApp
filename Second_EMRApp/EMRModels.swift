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
    public enum Gender: String, Codable, CaseIterable, Identifiable {
        case male = "Male"
        case female = "Female"
        case other = "Other"

        public var id: String { rawValue }
        public struct Patient: Identifiable, Codable, Hashable {
            public var id: UUID = UUID()
            public var nameEnglish: String = ""
            public var nameArabic: String = ""
            public var dob: Date = Date()
            public var gender: Gender = .male   // ✅ default
            
            // …rest of fields
        }
    }

    // Soft delete (optional but handy later)
    public var isDeleted: Bool = false

    public init() {}
}

