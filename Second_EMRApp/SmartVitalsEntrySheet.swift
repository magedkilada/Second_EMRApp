import SwiftUI

struct SmartVitalsEntrySheet: View {
    
    let patient: Patient
    @Binding var vitals: SmartVitalsEntry
    
    let onCancel: () -> Void
    let onInsertIntoNote: (SmartVitalsEntry) -> Void
    let onSaveOnly: (SmartVitalsEntry) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Insert will place vitals as the first line under Objective / Physical Exam (if present).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Blood Pressure") {
                    bpFields()
                }
                
                Section("Vitals") {
                    otherVitalsFields()
                }
            }
            .navigationTitle("Smart Vitals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                
                // ✅ YES: this is the “Done” placement
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Done") {
                        Button("Save only") {
                            onSaveOnly(vitals)
                            dismiss()
                        }
                        Button("Save & Insert into Note") {
                            onInsertIntoNote(vitals)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Fields
    
    private func bpFields() -> some View {
        HStack {
            intField("SBP", value: $vitals.sbp)
            intField("DBP", value: $vitals.dbp)
        }
    }
    
    private func otherVitalsFields() -> some View {
        VStack(spacing: 12) {

            HStack {
                numberField("Temp °C", value: $vitals.tempC)
                intField("HR", value: $vitals.hr)
            }

            HStack {
                intField("SpO₂ %", value: $vitals.spo2)
                Spacer()
            }

            HStack {
                numberField("Wt kg", value: $vitals.weightKg)
                numberField("Ht cm", value: $vitals.heightCm)
            }

            // Optional: for <5 years
            HStack {
                numberField("Head Circ cm", value: $vitals.headCircumferenceCm)
                Spacer()
            }
        }
    }
    }
    
    // MARK: - Field Helpers
    
private func intField(_ title: String, value: Binding<Int?>) -> some View {
    TextField(title, value: value, format: .number)
        .mobileKeyboard(.numberPad)
        .textFieldStyle(.roundedBorder)
}

private func numberField(_ title: String, value: Binding<Double?>) -> some View {
    TextField(title, value: value, format: .number)
        .mobileKeyboard(.decimalPad)
        .textFieldStyle(.roundedBorder)
}


