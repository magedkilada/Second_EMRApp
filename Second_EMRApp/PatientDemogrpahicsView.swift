import SwiftUI

struct PatientDemographicsView: View {

    // MARK: - Inputs
    @Binding var patient: Patient
    let onSaveAndNew: () -> Void
    let onRequestDelete: () -> Void
    let onPrint: (() -> Void)?

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore

    // MARK: - Local UI state
    @State private var showDeleteConfirm = false
    @State private var showDupAlert = false
    @State private var dupMessage: String = ""

    // MARK: - Derived
    private var duplicatePassport: Bool {
        let v = patient.passport.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return false }
        return store.patients.contains(where: { !$0.isDeleted && $0.id != patient.id && $0.passport == v })
    }

    private var duplicateNationalID: Bool {
        let v = patient.nationalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return false }
        return store.patients.contains(where: { !$0.isDeleted && $0.id != patient.id && $0.nationalID == v })
    }

    private var hasDuplicateID: Bool { duplicatePassport || duplicateNationalID }

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
                                    touch()
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
                            .onChange(of: patient.gender) { _, _ in touch() }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Identifiers") {
                    VStack(alignment: .leading, spacing: 12) {

                        labeledTextField("MRN (CAPS + digits only)", text: $patient.mrn)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: patient.mrn) { _, newValue in
                                let filtered = filterUpperAlnum(newValue)
                                if filtered != newValue { patient.mrn = filtered }
                                touch()
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("National ID (digits only)").font(.headline)
                            TextField("National ID", text: $patient.nationalID)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .onChange(of: patient.nationalID) { _, newValue in
                                    let filtered = filterDigits(newValue)
                                    if filtered != newValue { patient.nationalID = filtered }
                                    touch()
                                }

                            if duplicateNationalID {
                                Text("⚠️ Another patient already has this National ID.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Passport (CAPS + digits)").font(.headline)
                            TextField("Passport", text: $patient.passport)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onChange(of: patient.passport) { _, newValue in
                                    let filtered = filterUpperAlnum(newValue)
                                    if filtered != newValue { patient.passport = filtered }
                                    touch()
                                }

                            if duplicatePassport {
                                Text("⚠️ Another patient already has this Passport #.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Contact") {
                    VStack(alignment: .leading, spacing: 12) {

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Phone (+ and digits)").font(.headline)
                            TextField("Phone", text: $patient.phone)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.phonePad)
                                // KEY FIX: sanitize on every change + keep '+' as real character (not floating)
                                .onChange(of: patient.phone) { _, newValue in
                                    let filtered = filterPhonePlusDigits(newValue)
                                    if filtered != newValue { patient.phone = filtered }
                                    touch()
                                }
                        }

                        labeledTextField("Email", text: $patient.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: patient.email) { _, _ in touch() }
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

                    Button {
                        if hasDuplicateID {
                            dupMessage = [
                                duplicatePassport ? "Passport # is duplicated." : nil,
                                duplicateNationalID ? "National ID is duplicated." : nil
                            ].compactMap { $0 }.joined(separator: "\n")
                            showDupAlert = true
                            return
                        }
                        onSaveAndNew()
                    } label: {
                        Label("Save & New", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hasDuplicateID)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog(
                        "Delete this patient?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) { onRequestDelete() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This will remove the patient from the list (soft delete).")
                    }
                }
                .padding(.top, 6)
            }
            .padding()
        }
        .navigationTitle("Demographics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cannot Save", isPresented: $showDupAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(dupMessage)
        }
    }

    // MARK: - Helpers

    private func touch() {
        patient.updatedAt = Date()
    }

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
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { action() }
    }

    // MARK: - Filters

    private func filterDigits(_ s: String) -> String {
        s.filter { $0.isNumber }
    }

    private func filterUpperAlnum(_ s: String) -> String {
        let up = s.uppercased()
        return up.filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
    }

    private func filterPhonePlusDigits(_ s: String) -> String {
        // Allow exactly one leading '+', everything else digits.
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        var usedPlus = false
        for ch in trimmed {
            if ch == "+" && !usedPlus && out.isEmpty {
                out.append(ch)
                usedPlus = true
            } else if ch.isNumber {
                out.append(ch)
            }
        }
        return out
    }
}
