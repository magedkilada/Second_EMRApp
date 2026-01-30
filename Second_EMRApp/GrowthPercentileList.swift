import SwiftUI
import Foundation

struct GrowthPercentileList: View {

    let vitals: [SmartVitalsEntry]
    let patientDOB: Date
    let metric: GrowthMetric
    let sex: GrowthSex

    var body: some View {
        let rows = percentileRows()

        VStack(alignment: .leading, spacing: 10) {

            header(rowsCount: rows.count)

            if rows.isEmpty {
                ContentUnavailableView(
                    "No vitals to chart",
                    systemImage: "waveform.path.ecg",
                    description: Text("Enter Weight/Height/HC vitals and ensure DOB is set.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                List(rows) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.date, style: .date)
                                .font(.subheadline)

                            Text("Age: \(r.ageText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(r.valueText)
                                .font(.headline)

                            if let p = r.percentile {
                                Text("P\(Int(p.rounded()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .frame(maxHeight: 320)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(rowsCount: Int) -> some View {
        let ds = GrowthStore.shared.datasetFor(
            standard: .who_0_2,
            metric: metric,
            sex: sex
        ) != nil ? "Loaded" : "Missing"

        HStack(spacing: 10) {
            Text("Vitals: \(vitals.count)")
            Text("Rows: \(rowsCount)")
            Text("Dataset: \(ds)")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Percentile lookup

    private func percentileFor(value: Double, ageDays: Int, standard: GrowthStandard) -> Double? {

        // This matches filenames like:
        // who_0_2_weightForAge_female.json
        let fileKey = "\(standard.rawValue)_\(metric.rawValue)_\(sex.rawValue)"

        guard let ds = GrowthStore.shared.datasetFor(standard: standard, metric: metric, sex: sex) else {
            print("❌ No dataset loaded for:", fileKey)
            return nil
        }

        let p = percentileFromLMS(value: value, ageDays: ageDays, dataset: ds)

        if p == nil {
            print("⚠️ Percentile nil for:", fileKey,
                  "ageDays:", ageDays,
                  "value:", value,
                  "rows:", ds.rows.count,
                  "unit:", ds.ageUnit)
            if let r0 = ds.rows.first {
                print("   first row age:", r0.age, "L:", r0.L, "M:", r0.M, "S:", r0.S)
            }
        }

        return p
    }

    // MARK: - Row model

    private struct Row: Identifiable {
        let id = UUID()
        let date: Date
        let ageDays: Int
        let value: Double
        let unit: String
        let percentile: Double?

        var ageText: String {
            if ageDays < 365 {
                let mo = Double(ageDays) / 30.4375
                return String(format: "%.1f mo", mo)
            } else {
                let yr = Double(ageDays) / 365.25
                return String(format: "%.2f y", yr)
            }
        }

        var valueText: String {
            String(format: "%.1f %@", value, unit)
        }
    }

    // MARK: - Build rows

    private func percentileRows() -> [Row] {

        let extracted: [(date: Date, ageDays: Int, value: Double, unit: String)] =
        vitals.compactMap { v in
            let ageDays = max(0, daysBetween(patientDOB, v.recordedAt))

            switch metric {
            case .weightForAge:
                guard let w = v.weightKg, w > 0 else { return nil }
                return (v.recordedAt, ageDays, w, "kg")

            case .heightForAge:
                guard let h = v.heightCm, h > 0 else { return nil }
                return (v.recordedAt, ageDays, h, "cm")

            case .headCircForAge:
                guard let hc = v.headCircumferenceCm, hc > 0 else { return nil }
                return (v.recordedAt, ageDays, hc, "cm")
            }
        }
        .sorted { $0.date < $1.date }

        // WHO for <2y, CDC for >=2y (when you add CDC later)
        return extracted.map { item in
            let standard: GrowthStandard = (item.ageDays >= 730) ? .cdc_2_20 : .who_0_2
            let p = percentileFor(value: item.value, ageDays: item.ageDays, standard: standard)
            return Row(date: item.date, ageDays: item.ageDays, value: item.value, unit: item.unit, percentile: p)
        }
    }

    // MARK: - LMS percentile math

    private func percentileFromLMS(value: Double, ageDays: Int, dataset: LMSDataset) -> Double? {

        let rows = dataset.rows.sorted { $0.age < $1.age }
        guard !rows.isEmpty else { return nil }

        // Convert internal ageDays into dataset unit (Int axis)
        let targetAge: Int
        switch dataset.ageUnit {
        case .days:
            targetAge = ageDays
        case .months:
            targetAge = Int((Double(ageDays) / 30.4375).rounded())
        }

        // nearest age row
        guard let row = rows.min(by: { abs($0.age - targetAge) < abs($1.age - targetAge) }) else {
            return nil
        }

        let z = GrowthMath.zScore(value: value, L: row.L, M: row.M, S: row.S)
        guard z.isFinite else { return nil }

        return percentileFromZ(z)
    }

    private func percentileFromZ(_ z: Double) -> Double {
        // Standard normal CDF using erf
        let phi = 0.5 * (1.0 + erf(z / sqrt(2.0)))
        return phi * 100.0
    }

    // MARK: - Date helper

    private func daysBetween(_ dob: Date, _ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: dob, to: d).day ?? 0
    }
}
