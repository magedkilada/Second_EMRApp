import SwiftUI
import Charts

struct GrowthChartRendererView: View {

    let vitals: [SmartVitalsEntry]
    let patientDOB: Date
    let metric: GrowthMetric
    let sex: GrowthSex

    var body: some View {

        let points = buildPatientPoints()

        VStack(alignment: .leading, spacing: 8) {

            // tiny debug line
            Text("Points: \(points.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if points.isEmpty {
                ContentUnavailableView(
                    "No vitals to chart",
                    systemImage: "waveform.path.ecg",
                    description: Text("Enter Weight/Height/HC and ensure DOB is set.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                Chart {
                    ForEach(points) { p in
                        PointMark(
                            x: .value("Age", p.ageYears),
                            y: .value("Value", p.value)
                        )
                        .symbolSize(70)
                    }
                }
                .chartXAxisLabel("Age (years)")
                .chartYAxisLabel(yLabel())
                .frame(minHeight: 280)
            }
        }
    }

    // MARK: - Private model (UNIQUE NAME)

    private struct GrowthPatientPoint: Identifiable {
        let id = UUID()
        let ageYears: Double
        let value: Double
        let date: Date
    }

    // MARK: - Build points

    private func buildPatientPoints() -> [GrowthPatientPoint] {

        let items: [(date: Date, ageDays: Int, value: Double)] = vitals.compactMap { v in
            let ageDays = max(0, daysBetween(patientDOB, v.recordedAt))

            let value: Double?
            switch metric {
            case .weightForAge: value = v.weightKg
            case .heightForAge: value = v.heightCm
            case .headCircForAge: value = v.headCircumferenceCm
            }

            guard let val = value, val > 0 else { return nil }
            return (v.recordedAt, ageDays, val)
        }

        return items
            .sorted { $0.date < $1.date }
            .map { item in
                GrowthPatientPoint(
                    ageYears: Double(item.ageDays) / 365.25,
                    value: item.value,
                    date: item.date
                )
            }
    }

    private func yLabel() -> String {
        switch metric {
        case .weightForAge: return "Weight (kg)"
        case .heightForAge: return "Height (cm)"
        case .headCircForAge: return "Head Circ (cm)"
        }
    }

    private func daysBetween(_ dob: Date, _ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: dob, to: d).day ?? 0
    }
}
