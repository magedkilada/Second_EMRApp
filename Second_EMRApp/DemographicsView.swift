import SwiftUI

struct DemographicsView: View {
    let patient: Patient
    @EnvironmentObject private var store: EMRStore
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCannotDeleteAlert = false
    @State private var showingDuplicateAlert = false
    @State private var duplicateAlertMessage = ""
    @State private var showingEmailWarning = false

    @Environment(\.presentationMode) var presentationMode

    @State private var editedNameEnglish: String = ""
    @State private var editedNameArabic: String = ""
    @State private var editedMRN: String = ""
    @State private var editedNationalID: String = ""
    @State private var editedDOB: Date = Date()
    @State private var editedGender: Gender = .male
    @State private var editedPhone: String = ""
    @State private var editedEmail: String = ""
    @State private var editedPassport: String = ""

    var body: some View {
        Form {
            Section(header: Text("Patient Information")) {
                if isEditing {
                    TextField("English Name", text: $editedNameEnglish)
                    TextField("Arabic Name", text: $editedNameArabic)
                        .environment(\.layoutDirection, .rightToLeft)
                        .multilineTextAlignment(.trailing)
                    TextField("MRN (letters + digits)", text: $editedMRN)
                        .mobileAutocapitalization(.characters)
                        .onChange(of: editedMRN) { _, newValue in
                            editedMRN = newValue.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
                        }
                    TextField("National ID (digits only)", text: $editedNationalID)
                        .mobileKeyboard(.numberPad)
                        .onChange(of: editedNationalID) { _, newValue in
                            editedNationalID = newValue.filter(\.isNumber)
                        }
                    TextField("Passport (letters + digits)", text: $editedPassport)
                        .mobileAutocapitalization(.characters)
                        .onChange(of: editedPassport) { _, newValue in
                            editedPassport = newValue.uppercased().filter { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
                        }
                    DatePicker("Date of Birth", selection: $editedDOB, displayedComponents: .date)
                    Picker("Gender", selection: $editedGender) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                } else {
                    HStack {
                        Text("English Name")
                        Spacer()
                        Text(patient.nameEnglish)
                            .foregroundColor(.secondary)
                    }
                    if !patient.nameArabic.isEmpty {
                        HStack {
                            Text("Arabic Name")
                            Spacer()
                            Text(patient.nameArabic)
                                .foregroundColor(.secondary)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                    HStack {
                        Text("MRN")
                        Spacer()
                        Text(patient.mrn)
                            .foregroundColor(.secondary)
                    }
                    if !patient.nationalID.isEmpty {
                        HStack {
                            Text("National ID")
                            Spacer()
                            Text(patient.nationalID)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !patient.passport.isEmpty {
                        HStack {
                            Text("Passport")
                            Spacer()
                            Text(patient.passport)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Date of Birth")
                        Spacer()
                        Text(patient.dob, style: .date)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Age")
                        Spacer()
                        Text(patient.ageString ?? "—")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Gender")
                        Spacer()
                        Text(patient.gender.rawValue)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Contact Information")) {
                if isEditing {
                    TextField("Phone Number", text: $editedPhone)
                        .mobileKeyboard(.phonePad)
                        .onChange(of: editedPhone) { _, newValue in
                            editedPhone = newValue.filter { $0.isNumber || $0 == "+" }
                        }
                    TextField("Email", text: $editedEmail)
                        .mobileKeyboard(.emailAddress)
                        .mobileAutocapitalization(.never)
                } else {
                    if !patient.phone.isEmpty {
                        HStack {
                            Text("Phone")
                            Spacer()
                            Text(patient.phone)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !patient.email.isEmpty {
                        HStack {
                            Text("Email")
                            Spacer()
                            Text(patient.email)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(header: Text("Record Statistics")) {
                HStack {
                    Text("Medical Records")
                    Spacer()
                    Text("\(store.recordsForPatient(patient.id).count)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Vitals Recorded")
                    Spacer()
                    Text("\(store.vitalsForPatient(patient.id).count)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Attachments")
                    Spacer()
                    Text("\(totalAttachments)")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(role: .destructive, action: {
                    attemptDeletePatient()
                }) {
                    HStack {
                        Spacer()
                        Text("Delete Patient")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Demographics")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Edit") {
                    if isEditing {
                        saveChanges()
                    } else {
                        startEditing()
                    }
                }
            }
        }
        .alert("Cannot Delete Patient", isPresented: $showingCannotDeleteAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This patient has \(store.recordsForPatient(patient.id).count) medical record(s). Please delete all medical records before deleting the patient.")
        }
        .alert("Delete Patient", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePatient()
            }
        } message: {
            Text("Are you sure you want to permanently delete \(patient.nameEnglish)? This action cannot be undone.")
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

    private var totalAttachments: Int {
        store.attachmentsForPatient(patient.id).count
    }

    private func startEditing() {
        editedNameEnglish = patient.nameEnglish
        editedNameArabic = patient.nameArabic
        editedMRN = patient.mrn
        editedNationalID = patient.nationalID
        editedPassport = patient.passport
        editedDOB = patient.dob
        editedGender = patient.gender
        editedPhone = patient.phone
        editedEmail = patient.email
        isEditing = true
    }

    private func saveChanges() {
        // Check email validity
        if !editedEmail.isEmpty && !isValidEmail(editedEmail) {
            showingEmailWarning = true
            return
        }

        // Check uniqueness
        if let msg = checkUniqueness() {
            duplicateAlertMessage = msg
            showingDuplicateAlert = true
            return
        }

        var updatedPatient = patient
        updatedPatient.nameEnglish = editedNameEnglish
        updatedPatient.nameArabic = editedNameArabic
        updatedPatient.mrn = editedMRN
        updatedPatient.nationalID = editedNationalID
        updatedPatient.passport = editedPassport
        updatedPatient.dob = editedDOB
        updatedPatient.gender = editedGender
        updatedPatient.phone = editedPhone
        updatedPatient.email = editedEmail
        updatedPatient.updatedAt = Date()

        store.updatePatient(updatedPatient)
        isEditing = false
    }

    private func checkUniqueness() -> String? {
        let others = store.patients.filter { $0.id != patient.id && !$0.isDeleted }

        if !editedMRN.isEmpty,
           others.contains(where: { $0.mrn == editedMRN }) {
            return "Another patient already has MRN \"\(editedMRN)\"."
        }
        if !editedNationalID.isEmpty,
           others.contains(where: { $0.nationalID == editedNationalID }) {
            return "Another patient already has National ID \"\(editedNationalID)\"."
        }
        if !editedPassport.isEmpty,
           others.contains(where: { $0.passport == editedPassport }) {
            return "Another patient already has Passport \"\(editedPassport)\"."
        }
        return nil
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func attemptDeletePatient() {
        if store.recordsForPatient(patient.id).isEmpty {
            showingDeleteConfirmation = true
        } else {
            showingCannotDeleteAlert = true
        }
    }

    private func deletePatient() {
        store.deletePatient(patient.id)
        presentationMode.wrappedValue.dismiss()
    }
}
