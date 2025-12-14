import SwiftUI

struct PatientDemographicsView: View {
    @Binding var patient: Patient
    let onSave: () -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        Form {

            Section("Name") {
                TextField("Name (English)", text: $patient.nameEnglish)
                TextField("Name (Arabic)", text: $patient.nameArabic)
            }

            Section("Date of Birth") {
                DatePicker("DOB *", selection: $patient.dob, displayedComponents: .date)
                    .onChange(of: patient.dob) { _, newValue in
                        patient.dob = min(newValue, Date())
                    }
            }

            Section("Sex") {
                // Replace with your actual Picker when model is wired
                Text("Sex field pending model link")
                    .foregroundStyle(.secondary)
            }

            Section("Identifiers") {
                TextField("Medical Record Number (digits only)", text: $patient.mrn)
                    .keyboardType(.numberPad)
                    .onChange(of: patient.mrn) { _, newValue in
                        patient.mrn = digitsOnly(newValue)
                    }

                TextField("National ID (digits only)", text: $patient.nationalID)
                    .keyboardType(.numberPad)
                    .onChange(of: patient.nationalID) { _, newValue in
                        patient.nationalID = digitsOnly(newValue)
                    }

                TextField("Passport (CAPS + digits)", text: $patient.passport)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: patient.passport) { _, newValue in
                        patient.passport = passportFilter(newValue)
                    }
            }

            Section("Contact") {
                TextField("Phone *", text: $patient.phone)
                    .keyboardType(.phonePad)
                    .onChange(of: patient.phone) { _, newValue in
                        patient.phone = digitsOnly(newValue)
                    }

                TextField("Email", text: $patient.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            Section(footer: Text("Required: Name (English), DOB (not future), Phone.")) {
                EmptyView()
            }
        }
    }

    private func digitsOnly(_ s: String) -> String { s.filter(\.isNumber) }

    private func passportFilter(_ s: String) -> String {
        s.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
    }
}
