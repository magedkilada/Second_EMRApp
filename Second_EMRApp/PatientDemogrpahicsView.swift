import SwiftUI

struct PatientDemographicsView: View {
    @Binding var patient: Patient
    let onSave: () -> Void
    let onRequestDelete: () -> Void

    @EnvironmentObject private var store: EMRStore
    @State private var showingDuplicateAlert = false
    @State private var duplicateAlertMessage = ""
    @State private var showingEmailWarning = false

    private var ageText: String {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: patient.dob, to: now)
        let y = max(0, comps.year ?? 0)
        let m = max(0, comps.month ?? 0)
        if y > 0 {
            return m > 0 ? "\(y)y \(m)m" : "\(y)y"
        } else {
            return "\(m)m"
        }
    }

    var body: some View {
        Form {

            Section("Name") {
                TextField("Name (English) *", text: $patient.nameEnglish)
                TextField("Name (Arabic)", text: $patient.nameArabic)
                    .environment(\.layoutDirection, .rightToLeft)
                    .multilineTextAlignment(.trailing)
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
                TextField("Medical Record Number (CAPS + digits)", text: $patient.mrn)
                    .mobileAutocapitalization(.characters)
                    .onChange(of: patient.mrn) { _, newValue in
                        patient.mrn = newValue.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
                    }

                TextField("National ID (digits only)", text: $patient.nationalID)
                    .mobileKeyboard(.numberPad)
                    .onChange(of: patient.nationalID) { _, newValue in
                        patient.nationalID = newValue.filter(\.isNumber)
                    }

                TextField("Passport (CAPS + digits)", text: $patient.passport)
                    .mobileAutocapitalization(.characters)
                    .onChange(of: patient.passport) { _, newValue in
                        patient.passport = newValue.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
                    }
            }

            Section("Contact") {
                TextField("Phone *", text: $patient.phone)
                    .mobileKeyboard(.phonePad)
                    .onChange(of: patient.phone) { _, newValue in
                        patient.phone = newValue.filter { $0.isNumber || $0 == "+" }
                    }

                TextField("Email", text: $patient.email)
                    .mobileKeyboard(.emailAddress)
                    .mobileAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }

            Section {
                Button { attemptSave() } label: {
                    Label("Save Patient", systemImage: "checkmark.circle")
                }

                Button(role: .destructive) { onRequestDelete() } label: {
                    Label("Delete Patient", systemImage: "trash")
                }
            } footer: {
                Text("Required: Name (English), DOB (not future), Phone.")
            }
        }
        .alert("Duplicate Identifier", isPresented: $showingDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(duplicateAlertMessage)
        }
        .alert("Invalid Email", isPresented: $showingEmailWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The email address entered does not appear to be valid.")
        }
    }

    private func attemptSave() {
        // Email validation
        if !patient.email.isEmpty && !isValidEmail(patient.email) {
            showingEmailWarning = true
            return
        }

        // Uniqueness check
        if let msg = checkUniqueness() {
            duplicateAlertMessage = msg
            showingDuplicateAlert = true
            return
        }

        onSave()
    }

    private func checkUniqueness() -> String? {
        let others = store.patients.filter { $0.id != patient.id && !$0.isDeleted }

        if !patient.mrn.isEmpty,
           others.contains(where: { $0.mrn == patient.mrn }) {
            return "Another patient already has MRN \"\(patient.mrn)\"."
        }
        if !patient.nationalID.isEmpty,
           others.contains(where: { $0.nationalID == patient.nationalID }) {
            return "Another patient already has National ID \"\(patient.nationalID)\"."
        }
        if !patient.passport.isEmpty,
           others.contains(where: { $0.passport == patient.passport }) {
            return "Another patient already has Passport \"\(patient.passport)\"."
        }
        return nil
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
