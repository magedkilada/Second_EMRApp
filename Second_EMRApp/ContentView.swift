import SwiftUI

struct ContentView: View {

    @StateObject private var store = EMRStore()

    @State private var searchText: String = ""
    @State private var confirmDeleteID: UUID? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $store.selectedPatientID) {
            ForEach(filteredPatients, id: \.id) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.nameEnglish.isEmpty ? "Unnamed (English)" : p.nameEnglish)
                        .font(.headline)
                    if !p.nameArabic.isEmpty {
                        Text(p.nameArabic)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !p.mrn.isEmpty {
                        Text("MRN: \(p.mrn)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(p.id)
                .contextMenu {
                    Button(role: .destructive) {
                        confirmDeleteID = p.id
                    } label: {
                        Label("Delete Patient", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Patients")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search name / MRN / phone")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.addNewPatient()
                } label: {
                    Label("Add Patient", systemImage: "plus")
                }
            }
        }
        .alert("Delete patient?", isPresented: Binding(
            get: { confirmDeleteID != nil },
            set: { if !$0 { confirmDeleteID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    store.deletePatient(id: id)
                }
                confirmDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteID = nil
            }
        } message: {
            Text("This will permanently delete this patient from this device (local storage).")
        }
    }

    private var filteredPatients: [Patient] {
        let base = store.patients.filter { !$0.isDeleted }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }

        let lower = q.lowercased()
        return base.filter { p in
            p.nameEnglish.lowercased().contains(lower)
            || p.nameArabic.lowercased().contains(lower)
            || p.mrn.contains(q)
            || p.phone.contains(q)
            || p.nationalID.contains(q)
            || p.passport.contains(q.uppercased())
            || p.email.lowercased().contains(lower)
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let id = store.selectedPatientID,
               let binding = store.patientBinding(for: id) {
                PatientDemographicsView(patient: binding)
                    .navigationTitle("Demographics")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView(
                    "No Patient Selected",
                    systemImage: "person.text.rectangle",
                    description: Text("Add a patient, then select them from the list.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

// MARK: - Demographics Form

private struct PatientDemographicsView: View {
    @Binding var patient: Patient

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name (English)", text: $patient.nameEnglish)
                TextField("Name (Arabic)", text: $patient.nameArabic)
            }

            Section("Date of Birth") {
                DatePicker(
                    "DOB",
                    selection: Binding(
                        get: { patient.dob },
                        set: { patient.dob = EMRValidation.clampDOB($0) }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
            }

            Section("Identifiers") {
                TextField("Medical Record Number (digits only)", text: Binding(
                    get: { patient.mrn },
                    set: { patient.mrn = EMRValidation.digitsOnly($0) }
                ))
                .keyboardType(.numberPad)

                TextField("National ID (digits only)", text: Binding(
                    get: { patient.nationalID },
                    set: { patient.nationalID = EMRValidation.digitsOnly($0) }
                ))
                .keyboardType(.numberPad)

                TextField("Passport (CAPS + digits)", text: Binding(
                    get: { patient.passport },
                    set: { patient.passport = EMRValidation.sanitizePassport($0) }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
            }

            Section("Contact") {
                TextField("Phone (+ and digits)", text: Binding(
                    get: { patient.phone },
                    set: { patient.phone = EMRValidation.sanitizePhone($0) }
                ))
                .keyboardType(.phonePad)

                TextField("Email", text: Binding(
                    get: { patient.email },
                    set: { patient.email = EMRValidation.sanitizeEmail($0) }
                ))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            }
        }
    }
}
