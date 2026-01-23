import SwiftUI

struct VitalsChartView: View {

    let vitals: [SmartVitalsEntry]
    let patientDOB: Date

    @State private var metric: GrowthMetric = .weightForAge
    @State private var sex: GrowthSex = .male

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 12) {
                Picker("", selection: $metric) {
                    Text("Weight").tag(GrowthMetric.weightForAge)
                    Text("Height").tag(GrowthMetric.heightForAge)
                    Text("Head Circ").tag(GrowthMetric.headCircForAge)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Picker("", selection: $sex) {
                    Text("Male").tag(GrowthSex.male)
                    Text("Female").tag(GrowthSex.female)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer()
            }

            GrowthChartRendererView(vitals: vitals, patientDOB: patientDOB, metric: metric, sex: sex)
            GrowthPercentileList(vitals: vitals, patientDOB: patientDOB, metric: metric, sex: sex)
        }
        .padding(.vertical, 8)
    }
}
