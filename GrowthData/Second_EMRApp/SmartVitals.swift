import Foundation

public struct SmartVitalsEntry: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var patientID: UUID
    public var recordedAt: Date = Date()

    // Inputs
    public var tempC: Double? = nil
    public var sbp: Int? = nil
    public var dbp: Int? = nil
    public var hr: Int? = nil
    public var spo2: Int? = nil
    public var weightKg: Double? = nil
    public var heightCm: Double? = nil
    public var headCircumferenceCm: Double? = nil  // <5y typically

    // Derived
    public var bmi: Double? {
        guard let w = weightKg, let hcm = heightCm, hcm > 0 else { return nil }
        let hm = hcm / 100.0
        let v = w / (hm * hm)
        return (v * 10).rounded() / 10.0
    }

    // Future: percentiles (hook for later WHO/CDC tables)
    public var weightPercentile: Double? = nil
    public var heightPercentile: Double? = nil
    public var headCircPercentile: Double? = nil

    public init(patientID: UUID) {
        self.patientID = patientID
    }

    public func formattedBlock(includePercentiles: Bool = false, isUnder5: Bool) -> String {
        var parts: [String] = []
        if let t = tempC { parts.append("Temp \(String(format: "%.1f", t))°C") }
        if let s = sbp, let d = dbp { parts.append("BP \(s)/\(d)") }
        if let h = hr { parts.append("HR \(h)") }
        if let o = spo2 { parts.append("SpO₂ \(o)%") }
        if let w = weightKg { parts.append("Wt \(String(format: "%.1f", w)) kg") }
        if let ht = heightCm { parts.append("Ht \(String(format: "%.1f", ht)) cm") }
        if isUnder5, let hc = headCircumferenceCm { parts.append("HC \(String(format: "%.1f", hc)) cm") }
        if let b = bmi { parts.append("BMI \(String(format: "%.1f", b))") }

        // Percentiles later (kept optional now)
        if includePercentiles {
            if let p = weightPercentile { parts.append("Wt% \(String(format: "%.0f", p))") }
            if let p = heightPercentile { parts.append("Ht% \(String(format: "%.0f", p))") }
            if isUnder5, let p = headCircPercentile { parts.append("HC% \(String(format: "%.0f", p))") }
        }

        return parts.isEmpty ? "" : "Vitals: " + parts.joined(separator: " | ")
    }
}
