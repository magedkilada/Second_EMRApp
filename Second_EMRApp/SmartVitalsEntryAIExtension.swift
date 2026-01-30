import Foundation

// MARK: - SmartVitalsEntry Smart Formatting Extension
// Computes BMI for all patients.
// For patients under 5: weight-for-age, length-for-age, head-circ-for-age percentiles
// using WHO 0–2 LMS tables via GrowthReferences.

extension SmartVitalsEntry {

    /// Smart formatted block for insertion into notes.
    /// Automatically computes BMI and pediatric percentiles.
    @MainActor
    func formattedBlockCompact(patient: Patient, useAI: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: recordedAt)

        var lines: [String] = []

        // Line 1: Basic vitals
        var basicParts: [String] = []
        if let temp = tempC {
            basicParts.append("Temp: \(String(format: "%.1f", temp))\u{00B0}C")
        }
        if let hr = hr {
            basicParts.append("HR: \(hr) bpm")
        }
        if let systolic = sbp, let diastolic = dbp {
            basicParts.append("BP: \(systolic)/\(diastolic) mmHg")
        }
        if let spo2 = spo2 {
            basicParts.append("SpO\u{2082}: \(spo2)%")
        }
        if !basicParts.isEmpty {
            lines.append(basicParts.joined(separator: ", "))
        }

        // Line 2: Growth measurements + BMI
        var growthParts: [String] = []
        if let w = weightKg {
            growthParts.append("Weight: \(String(format: "%.1f", w)) kg")
        }
        if let h = heightCm {
            growthParts.append("Height: \(String(format: "%.1f", h)) cm")
        }
        if let hc = headCircumferenceCm {
            growthParts.append("HC: \(String(format: "%.1f", hc)) cm")
        }
        // BMI for all patients
        if let computedBMI = bmi {
            growthParts.append("BMI: \(String(format: "%.1f", computedBMI))")
        }
        if !growthParts.isEmpty {
            lines.append(growthParts.joined(separator: ", "))
        }

        // Line 3: Pediatric percentiles (under 5 years)
        let percentileLine = computePediatricPercentiles(patient: patient)
        if !percentileLine.isEmpty {
            lines.append(percentileLine)
        }

        if lines.isEmpty {
            return "VITALS (\(dateStr)): No measurements recorded"
        }

        return "VITALS (\(dateStr)):\n\(lines.joined(separator: "\n"))"
    }

    /// Compute WHO percentiles for patients under 5 years old.
    @MainActor
    private func computePediatricPercentiles(patient: Patient) -> String {
        let cal = Calendar.current
        let ageComponents = cal.dateComponents([.year, .month, .day], from: patient.dob, to: recordedAt)
        let ageYears = ageComponents.year ?? 0

        // Only compute for children under 5
        guard ageYears < 5 else { return "" }

        let ageDays = cal.dateComponents([.day], from: patient.dob, to: recordedAt).day ?? 0
        guard ageDays >= 0 else { return "" }

        let sex: GrowthSex
        switch patient.gender {
        case .male: sex = .male
        case .female: sex = .female
        case .other: sex = .male // default fallback
        }

        let refs = GrowthReferences.shared
        var parts: [String] = []

        // Weight-for-age percentile
        if let w = weightKg,
           let row = refs.lms(standard: .who_0_2, metric: .weightForAge, sex: sex, ageDays: ageDays) {
            let z = GrowthMath.zScore(value: w, L: row.L, M: row.M, S: row.S)
            if !z.isNaN {
                let pct = GrowthMath.percentile(fromZ: z)
                parts.append("Wt-for-age: P\(String(format: "%.0f", pct))")
            }
        }

        // Length/height-for-age percentile
        if let h = heightCm,
           let row = refs.lms(standard: .who_0_2, metric: .heightForAge, sex: sex, ageDays: ageDays) {
            let z = GrowthMath.zScore(value: h, L: row.L, M: row.M, S: row.S)
            if !z.isNaN {
                let pct = GrowthMath.percentile(fromZ: z)
                parts.append("Ht-for-age: P\(String(format: "%.0f", pct))")
            }
        }

        // Head circumference-for-age percentile
        if let hc = headCircumferenceCm,
           let row = refs.lms(standard: .who_0_2, metric: .headCircForAge, sex: sex, ageDays: ageDays) {
            let z = GrowthMath.zScore(value: hc, L: row.L, M: row.M, S: row.S)
            if !z.isNaN {
                let pct = GrowthMath.percentile(fromZ: z)
                parts.append("HC-for-age: P\(String(format: "%.0f", pct))")
            }
        }

        guard !parts.isEmpty else { return "" }
        return "Percentiles: " + parts.joined(separator: ", ")
    }
}
