import SwiftUI

struct ContentView: View {

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    // MARK: - UI State
    @State private var showPhysiciansManager = false
    @State private var showReferenceCenter = false
    @State private var showGlobalSearch = false

    @State private var confirmDeletePatientID: UUID? = nil

    // Sidebar search + filters
    @State private var patientSearchText: String = ""
    @State private var filterGender: Gender? = nil
    @State private var filterAgeBand: AgeBand? = nil
    @State private var filterHasNotes: Bool = false
    @State private var filterHasImaging: Bool = false
    @State private var showFilters = false
    @State private var globalSearchQuery: String = ""
    
    @Binding var query: String

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

            Section {
                AttendingPhysicianCard(onManage: { showPhysiciansManager = true })
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            } header: {
                Text("Treating Physician")
            }

            // ✅ NEW: Encounter / Clinic card (binds to selected patient)
            Section {
                EncounterTypeCard(patient: selectedPatientBinding)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            } header: {
                Text("Encounter")
            }

            // Filters (collapsible)
            Section(isExpanded: $showFilters) {
                PatientFilterChips(
                    gender: $filterGender,
                    ageBand: $filterAgeBand,
                    hasNotes: $filterHasNotes,
                    hasImaging: $filterHasImaging
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            } header: {
                Text("Filters")
            }

            Section("Patients") {

                ForEach(filteredPatientsForSidebar) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        highlightText(patientDisplayName(p), query: patientSearchText)
                            .font(.headline)

                        let secondary = patientSecondaryLine(p)
                        if !secondary.isEmpty {
                            highlightText(secondary, query: patientSearchText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(p.id as UUID?)
                }

                Button { addPatient() } label: {
                    Label("Add Patient", systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle("Neurosurgery EMR")
        .searchable(
            text: $patientSearchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search name, MRN, DOB, phone, ID…"
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {

                Button { showGlobalSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }

                Button { addPatient() } label: {
                    Image(systemName: "plus")
                }

                Button(role: .destructive) {
                    if let id = store.selectedPatientID { confirmDeletePatientID = id }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.selectedPatientID == nil)
            }
        }
        .sheet(isPresented: $showPhysiciansManager) {
            PhysiciansManagerView()
                .environmentObject(physicians)
        }
        .sheet(isPresented: $showReferenceCenter) {
            ReferencesCenterView()
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalRecordsSearchView(query: $globalSearchQuery)
                .environmentObject(store)
        }
        .alert("Delete patient?", isPresented: Binding(
            get: { confirmDeletePatientID != nil },
            set: { if !$0 { confirmDeletePatientID = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDeletePatientID = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmDeletePatientID { deletePatient(id) }
                confirmDeletePatientID = nil
            }
        } message: {
            Text("This will remove the patient and their data from this device.")
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let id = store.selectedPatientID,
               let idx = store.patients.firstIndex(where: { $0.id == id }) {

                PatientDetailHost(
                    patient: $store.patients[idx],
                    patientValueForRecords: store.patients[idx],
                    onSavePatient: { savePatientEditsAndStartNew(id: id) },
                    onRequestDelete: { confirmDeletePatientID = id }
                )

            } else {
                ContentUnavailableView("Select a patient", systemImage: "person")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Selected patient binding for Encounter card

    private var selectedPatientBinding: Binding<Patient>? {
        guard let id = store.selectedPatientID,
              let idx = store.patients.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $store.patients[idx]
    }

    // MARK: - Patient Filtering + Ranking

    private var filteredPatientsForSidebar: [Patient] {
        let q = patientSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var candidates = store.patients.filter { !$0.isDeleted }

        candidates = candidates.filter { p in
            if let g = filterGender, p.gender != g { return false }
            if let band = filterAgeBand {
                let age = p.dob.ageYears
                if !band.contains(age) { return false }
            }
            if filterHasNotes {
                let has = store.notes.contains(where: { $0.patientID == p.id })
                if !has { return false }
            }
            if filterHasImaging {
                let has = store.attachments.contains(where: { $0.patientID == p.id && $0.category == .radiology })
                if !has { return false }
            }
            return true
        }

        guard !q.isEmpty else {
            return candidates.sorted { patientDisplayName($0) < patientDisplayName($1) }
        }

        return candidates
            .map { p -> (Patient, Int) in (p, patientMatchScore(p, query: q)) }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return patientDisplayName(a.0) < patientDisplayName(b.0)
            }
            .map { $0.0 }
    }

    private func patientMatchScore(_ p: Patient, query q: String) -> Int {
        let en = p.nameEnglish.lowercased()
        let ar = p.nameArabic.lowercased()
        let mrn = p.mrn.lowercased()
        let phone = p.phone.lowercased()
        let nat = p.nationalID.lowercased()
        let pass = p.passport.lowercased()
        let email = p.email.lowercased()

        let dob1 = p.dob.formatted(date: .abbreviated, time: .omitted).lowercased()
        let dob2 = p.dob.formatted(date: .numeric, time: .omitted).lowercased()
        let dob3 = String(p.dob.ISO8601Format().prefix(10)).lowercased()

        var score = 0
        if en.contains(q) || ar.contains(q) { score += 100 }
        if mrn.contains(q) { score += 80 }
        if dob1.contains(q) || dob2.contains(q) || dob3.contains(q) { score += 60 }
        if phone.contains(q) { score += 40 }
        if nat.contains(q) { score += 30 }
        if pass.contains(q) { score += 25 }
        if email.contains(q) { score += 15 }
        if en.hasPrefix(q) || ar.hasPrefix(q) { score += 20 }
        if mrn.hasPrefix(q) { score += 15 }
        return score
    }

    // MARK: - Display helpers

    private func patientDisplayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }

    private func patientSecondaryLine(_ p: Patient) -> String {
        var parts: [String] = []

        let mrn = p.mrn.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mrn.isEmpty { parts.append("MRN: \(mrn)") }

        let dob = p.dob.formatted(date: .abbreviated, time: .omitted)
        parts.append("DOB: \(dob)")

        let phone = p.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty { parts.append("Phone: \(phone)") }

        // ✅ small hint for clinic patients (optional but useful)
        if p.encounterType == .clinic, let appt = p.appointmentDate {
            let t = appt.formatted(date: .omitted, time: .shortened)
            parts.append("Clinic: \(t)")
        }

        return parts.joined(separator: "  •  ")
    }

    private func highlightText(_ text: String, query: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Text(text) }
        return text.lowercased().contains(q) ? Text(text).bold() : Text(text)
    }

    // MARK: - Actions

    private func addPatient() {
        var p = Patient()
        p.createdAt = Date()
        p.updatedAt = Date()
        p.encounterType = .inpatient
        p.appointmentDate = nil
        store.patients.append(p)
        store.savePatients()
        store.selectedPatientID = p.id
    }

    private func deletePatient(_ id: UUID) {
        guard let idx = store.patients.firstIndex(where: { $0.id == id }) else { return }
        store.patients[idx].isDeleted = true
        store.savePatients()
        store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
    }

    /// ✅ New behavior you requested:
    /// Save demographics -> patient is committed -> immediately start a NEW blank patient
    private func savePatientEditsAndStartNew(id: UUID) {
        guard let idx = store.patients.firstIndex(where: { $0.id == id }) else { return }
        store.patients[idx].updatedAt = Date()
        store.savePatients()

        // Immediately ready for next entry
        addPatient()
    }
}

// MARK: - Patient detail host (tabs: Demographics / Medical Records)

private struct PatientDetailHost: View {

    @Binding var patient: Patient
    let patientValueForRecords: Patient

    let onSavePatient: () -> Void
    let onRequestDelete: () -> Void

    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {

            Picker("", selection: $tab) {
                Text("Demographics").tag(0)
                Text("Medical Records").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            Group {
                if tab == 0 {
                    PatientDemographicsView(
                        patient: $patient,
                        onSave: { onSavePatient() },
                        onRequestDelete: { onRequestDelete() }
                    )
                } else {
                    RecordsWorkspaceView(patient: patientValueForRecords)
                }
            }
        }
        .navigationTitle(titleForNavBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var titleForNavBar: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Patient"
    }
}

// MARK: - Encounter Card (Inpatient / Clinic + date + 10AM–10PM slots)

private struct EncounterTypeCard: View {
    var patient: Binding<Patient>?

    @State private var clinicDay: Date = Date()

    var body: some View {
        GroupBox {
            if let patient {
                VStack(alignment: .leading, spacing: 10) {

                    Picker("Encounter", selection: patient.encounterType) {
                        ForEach(EncounterType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if patient.wrappedValue.encounterType == .clinic {
                        // Date (day)
                        DatePicker("Date", selection: Binding(
                            get: {
                                patient.wrappedValue.appointmentDate ?? Date()
                            },
                            set: { newDate in
                                // keep time if already set, else default to 10:00 AM
                                let base = patient.wrappedValue.appointmentDate ?? defaultClinicTime(on: newDate)
                                patient.wrappedValue.appointmentDate = combine(day: newDate, timeFrom: base)
                            }
                        ), displayedComponents: [.date])

                        // Time slots
                        Menu {
                            let day = (patient.wrappedValue.appointmentDate ?? Date())
                            ForEach(clinicTimeSlots(for: day), id: \.self) { slot in
                                Button(slot.formatted(date: .omitted, time: .shortened)) {
                                    let currentDay = patient.wrappedValue.appointmentDate ?? day
                                    patient.wrappedValue.appointmentDate = combine(day: currentDay, timeFrom: slot)
                                }
                            }
                        } label: {
                            HStack {
                                Text("Time")
                                Spacer()
                                Text((patient.wrappedValue.appointmentDate ?? defaultClinicTime(on: Date()))
                                    .formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.down")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)

                    } else {
                        // Inpatient: clear appointment
                        if patient.wrappedValue.appointmentDate != nil {
                            Text("Clinic appointment cleared.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .onAppear {
                                    patient.wrappedValue.appointmentDate = nil
                                }
                        } else {
                            Text("Inpatient workflow")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Select a patient")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // ✅ Default clinic time: 10:00 AM
    private func defaultClinicTime(on day: Date) -> Date {
        var cal = Calendar.current
        cal.locale = .current
        return cal.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }

    // ✅ Combine day + time (keeps same day, replaces hour/minute)
    private func combine(day: Date, timeFrom: Date) -> Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: timeFrom)
        let m = cal.component(.minute, from: timeFrom)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
    }

    // ✅ Time slots 10:00 AM → 10:00 PM, every 15 min
    private func clinicTimeSlots(for day: Date) -> [Date] {
        var cal = Calendar.current
        cal.locale = .current

        guard let start = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day),
              let end = cal.date(bySettingHour: 22, minute: 0, second: 0, of: day) else {
            return []
        }

        var slots: [Date] = []
        var t = start
        while t <= end {
            slots.append(t)
            t = cal.date(byAdding: .minute, value: 15, to: t) ?? t.addingTimeInterval(15 * 60)
        }
        return slots
    }
}

// MARK: - Filters

private enum AgeBand: String, CaseIterable, Identifiable {
    case child = "0–17"
    case adult = "18–64"
    case senior = "65+"

    var id: String { rawValue }

    func contains(_ years: Int) -> Bool {
        switch self {
        case .child: return years >= 0 && years <= 17
        case .adult: return years >= 18 && years <= 64
        case .senior: return years >= 65
        }
    }
}

private struct PatientFilterChips: View {
    @Binding var gender: Gender?
    @Binding var ageBand: AgeBand?
    @Binding var hasNotes: Bool
    @Binding var hasImaging: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 8) {
                Menu {
                    Button("Any", role: .cancel) { gender = nil }
                    Divider()
                    ForEach(Gender.allCases) { g in
                        Button(g.rawValue) { gender = g }
                    }
                } label: {
                    chipLabel("Gender: \(gender?.rawValue ?? "Any")")
                }

                Menu {
                    Button("Any", role: .cancel) { ageBand = nil }
                    Divider()
                    ForEach(AgeBand.allCases) { b in
                        Button(b.rawValue) { ageBand = b }
                    }
                } label: {
                    chipLabel("Age: \(ageBand?.rawValue ?? "Any")")
                }
            }

            HStack(spacing: 8) {
                Toggle(isOn: $hasNotes) { chipLabel("Has Notes") }
                    .toggleStyle(.button)

                Toggle(isOn: $hasImaging) { chipLabel("Has Imaging") }
                    .toggleStyle(.button)
            }
        }
    }

    private func chipLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial)
            .clipShape(Capsule())
    }
}
