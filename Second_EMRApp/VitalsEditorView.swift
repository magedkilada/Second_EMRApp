import SwiftUI

struct VitalsEditorView: View {
    @Binding var vital: VitalsEntry
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    // 🔹 Editable text buffers (DO NOT bind TextField to Double)
    @State private var tempText = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var headCircText = ""


    var body: some View {
        NavigationStack {
            Form {
                Section("Measured") {
                    DatePicker("Date / Time", selection: $vital.measuredAt)
                }

                Section("Vitals") {
                    intField("Systolic BP", value: $vital.systolicBP)
                    intField("Diastolic BP", value: $vital.diastolicBP)
                    intField("Heart Rate", value: $vital.heartRate)
                    intField("SpO₂", value: $vital.spo2)

                    decimalField("Temp (°C)", text: $tempText, maxFractionDigits: 1) { vital.tempC = $0 }
                    decimalField("Weight (kg)", text: $weightText, maxFractionDigits: 1) { vital.weightKg = $0 }
                    decimalField("Height (cm)", text: $heightText, maxFractionDigits: 0) { vital.heightCm = $0 }
                    decimalField("Head Circ (cm)", text: $headCircText, maxFractionDigits: 1) { vital.headCircumferenceCm = $0 }
                }

                if let bmi = vital.bmi, bmi.isFinite {
                    Section("Derived") {
                        Text("BMI: \(String(format: "%.1f", bmi))")
                    }
                }
            }
            .navigationTitle("Vitals")
            .onAppear {
                tempText     = vital.tempC.map { String(format: "%.1f", $0) } ?? ""
                weightText   = vital.weightKg.map { String(format: "%.1f", $0) } ?? ""
                heightText   = vital.heightCm.map { String(format: "%.0f", $0) } ?? ""
                headCircText = vital.headCircumferenceCm.map { String(format: "%.1f", $0) } ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helpers (optional Int/Double fields)

    private func intField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0.filter { $0.isNumber }) }
        ))
        .keyboardType(.numberPad)
    }
    
    private func decimalField(
        _ title: String,
        text: Binding<String>,
        maxFractionDigits: Int,
        onCommitValue: @escaping (Double?) -> Void
    ) -> some View {
        TextField(title, text: Binding(
            get: { text.wrappedValue },
            set: { newValue in
                let sanitized = sanitizeDecimal(newValue, maxFractionDigits: maxFractionDigits)
                text.wrappedValue = sanitized
                onCommitValue(doubleOrNil(sanitized))
            }
        ))
        .keyboardType(.decimalPad)
    }

    private func doubleField(_ title: String, value: Binding<Double?>) -> some View {
        TextField(title, text: Binding(
            get: {
                guard let v = value.wrappedValue else { return "" }
                // Keep simple, avoid locale headaches for now
                return String(v)
            },
            set: {
                let filtered = $0.filter { "0123456789.".contains($0) }
                value.wrappedValue = Double(filtered)
            }
        ))
        .keyboardType(.decimalPad)
    }
    private func sanitizeDecimal(_ s: String, maxFractionDigits: Int = 1) -> String {
        // Allow empty
        if s.isEmpty { return "" }

        // Keep only digits and decimal point
        var filtered = s.filter { $0.isNumber || $0 == "." }

        // Only one dot
        if let firstDot = filtered.firstIndex(of: ".") {
            let after = filtered.index(after: firstDot)
            // Remove any extra dots
            let prefix = filtered[..<after]
            let rest = filtered[after...].replacingOccurrences(of: ".", with: "")
            filtered = String(prefix) + rest
        }

        // Limit fraction digits
        if let dot = filtered.firstIndex(of: ".") {
            let afterDot = filtered.index(after: dot)
            let frac = filtered[afterDot...]
            if frac.count > maxFractionDigits {
                let limited = frac.prefix(maxFractionDigits)
                filtered = String(filtered[..<afterDot]) + limited
            }
        }

        return filtered
    }

    private func doubleOrNil(_ s: String) -> Double? {
        // Treat "", "." as nil while editing
        if s.isEmpty || s == "." { return nil }
        return Double(s)
    }
}
