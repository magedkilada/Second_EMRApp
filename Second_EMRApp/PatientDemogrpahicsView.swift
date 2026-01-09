import SwiftUI

struct PatientDemographicsView: View {
    @Binding var patient: Patient
    let onSave: () -> Void
    let onRequestDelete: () -> Void

    // ✅ must be INSIDE the struct (so it can see `patient`)
    private var ageText: String {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: patient.dob, to: now)
        let y = max(0, comps.year ?? 0)
        let m = max(0, comps.month ?? 0)
        return "\(y) years \(m) months"
    }

    var body: some View {
        Form {

            Section("Name") {
                TextField("Name (English) *", text: $patient.nameEnglish)
                TextField("Name (Arabic)", text: $patient.nameArabic)
            }

            Section("Date of Birth") {
                DatePicker("DOB *", selection: $patient.dob, displayedComponents: .date)
                    .onChange(of: patient.dob) { _, newValue in
                        patient.dob = min(newValue, Date())
                    }

                HStack {
                    Text("Age")
                    Spacer()
                    Text(ageText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sex") {
                Picker("Sex", selection: $patient.gender) {
                    ForEach(Gender.allCases) { g in
                        Text(g.rawValue).tag(g)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Identifiers") {
                HStack(spacing: 8) {
                    TextField("MRN", text: $patient.mrn)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .onChange(of: patient.mrn) { _, newValue in
                            let filtered = newValue
                                .uppercased()
                                .filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
                            if filtered != newValue { patient.mrn = filtered }
                        }

                    Button {
                        UIPasteboard.general.string = patient.mrn
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(patient.mrn.isEmpty)
                    .help("Copy MRN")
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
                    .autocorrectionDisabled(true)
            }

            Section {
                Button { onSave() } label: {
                    Label("Save Patient", systemImage: "checkmark.circle")
                }

                Button(role: .destructive) { onRequestDelete() } label: {
                    Label("Delete Patient", systemImage: "trash")
                }
            } footer: {
                Text("Required: Name (English), DOB (not future), Phone.")
            }
        }
    }

    private func digitsOnly(_ s: String) -> String { s.filter(\.isNumber) }

    private func passportFilter(_ s: String) -> String {
        s.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
    }
}
