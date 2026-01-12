// VitalsEntry.swift  (NEW FILE – only ONE definition)
import Foundation

public struct VitalsEntry: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID
    public var measuredAt: Date = Date()

    // Vitals
    public var systolicBP: Int?
    public var diastolicBP: Int?
    public var heartRate: Int?
    public var spo2: Int?
    public var tempC: Double?
    public var weightKg: Double?
    public var heightCm: Double?
    public var headCircumferenceCm: Double?

    public init(patientID: UUID) {
        self.patientID = patientID
    }

    public var bmi: Double? {
        guard let w = weightKg, let h = heightCm, h > 0 else { return nil }
        let m = h / 100
        return w / (m * m)
    }

    public var bpString: String? {
        guard let s = systolicBP, let d = diastolicBP else { return nil }
        return "\(s)/\(d)"
    }
}
