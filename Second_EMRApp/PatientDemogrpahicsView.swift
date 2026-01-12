import SwiftUI
import UIKit

struct PatientDemographicsView: View {

    @Binding var patient: Patient
    let onSaveAndNew: () -> Void
    let onRequestDelete: () -> Void
    let onPrint: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {

                GroupBox("Patient") {
                    VStack(alignment: .leading, spacing: 12) {

                        labeledTextField("Name (English)", text: $patient.nameEnglish)
                            .textInputAutocapitalization(.words)

                        labeledTextField("Name (Arabic)", text: $patient.nameArabic)
                            .textInputAutocapitalization(.words)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("DOB").font(.headline)
                                Spacer()
                                Text(ageString(from: patient.dob))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            DatePicker("", selection: $patient.dob, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: patient.dob) { _, newValue in
                                    patient.dob = min(newValue, Date())
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sex").font(.headline)
                            Picker("", selection: $patient.gender) {
                                ForEach(Gender.allCases) { g in
                                    Text(g.rawValue).tag(g)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Identifiers") {
                    VStack(alignment: .leading, spacing: 12) {

                        labeledTextField("MRN (CAPS + digits only)", text: $patient.mrn)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        labeledTextField("National ID (digits only)", text: $patient.nationalID)
                            .keyboardType(.numberPad)

                        labeledTextField("Passport (CAPS + digits)", text: $patient.passport)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Contact") {
                    VStack(alignment: .leading, spacing: 12) {

                        labeledTextField("Phone (+ and digits)", text: $patient.phone)
                            .keyboardType(.phonePad)

                        labeledTextField("Email", text: $patient.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 12) {

                    if let onPrint {
                        Button { onPrintReliable(onPrint) } label: {
                            Label("Print", systemImage: "printer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button { onSaveAndNew() } label: {
                        Label("Save & New", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) { onRequestDelete() } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .padding()
        }
        .navigationTitle("Demographics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func labeledTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func ageString(from dob: Date) -> String {
        let cal = Calendar.current
        let years = cal.dateComponents([.year], from: dob, to: Date()).year ?? 0
        return "Age: \(max(0, years))"
    }

    private func onPrintReliable(_ action: @escaping () -> Void) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { action() }
    }
}
