//“BaselineContract"


import SwiftUI
import Combine

struct ContentView: View {

    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    @State private var showPhysiciansManager = false
    @State private var confirmDeletePatientID: UUID? = nil
    @State private var showBackupCenter: Bool = false

    // Sidebar UI
    @State private var censusScope: CensusScope = .clinic
    @State private var patientSearchText: String = ""

    @State private var filterGender: Gender? = nil
    @State private var filterAgeBand: AgeBand? = nil
    @State private var filterHasNotes: Bool = false
    @State private var filterHasImaging: Bool = false
    @State private var showFilters = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .onAppear {
            syncHeaderContext()
        }
        .onChange(of: physicians.selectedPhysicianID) { _, _ in
            syncHeaderContext()
        }
        .onChange(of: censusScope) { _, _ in
            syncHeaderContext()
        }
        // ✅ CRITICAL: when switching patients, clear right-pane selection
        .onChange(of: store.selectedPatientID) { _, _ in
            store.selectedNoteID = nil
            store.selectedAttachmentID = nil
            store.selectedVitalID = nil
        }
        .sheet(isPresented: $showBackupCenter) {
            BackupCenterView()
                .environmentObject(store)
                .environmentObject(physicians)
        }
    }
    
  
    
    static func demographicsPrintText(for patient: Patient) -> String {
        let nameEnglish = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameArabic  = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)

        let name: String = {
            if !nameEnglish.isEmpty { return nameEnglish }
            if !nameArabic.isEmpty { return nameArabic }
            return "Unnamed Patient"
        }()

        return """
        Name:  \(name)
        MRN:  \(patient.mrn)
        DOB:  \(patient.dob.formatted(date: .abbreviated, time: .omitted))
        Sex:  \(sexString(from: patient))
        Phone:  \(patient.phone)
        """
    }

    private static func sexString(from patient: Patient) -> String {
        // ✅ UNCOMMENT ONLY ONE LINE that matches EMRModels.swift

        // return patient.gender.rawValue
        // return patient.sex.rawValue
        // return patient.gender
        // return patient.sex

        return ""
    }
    
    private var detail: some View {
        Group {
            if let id = store.selectedPatientID,
               let idx = store.patients.firstIndex(where: { $0.id == id }) {

                PatientDetailHost(
                    patient: $store.patients[idx],
                    onSaveAndNewPatient: {
                        savePatientEdits(id: id)
                        addPatient()
                    },
                    onRequestDelete: {
                        confirmDeletePatientID = id
                    },
                    onPrintDemographics: {
                        let text = ContentView.demographicsPrintText(for: store.patients[idx])
                        EMRPrintHelper.printTextAsPDF(
                            text,
                            title: "Patient Demographics",
                            jobName: "Demographics"
                        )
                    }
                )
                .environmentObject(store)

            } else {
                ContentUnavailableView("Select a patient", systemImage: "person")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {

            List {

                // 2) Treating Physician
                Section("Treating Physician") {
                    AttendingPhysicianCard(onManage: { showPhysiciansManager = true })
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }

                // 3) Clinic / Inpatient
                Section("Clinic / Inpatient") {
                    ClinicInpatientCard(scope: $censusScope)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }

                // 4) Search + Filters
                Section("Search") {
                    PatientSearchRow(text: $patientSearchText)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }

                Section("Filters") {
                    Button {
                        showFilters.toggle()
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                // 5) Patients list (NO missing helper functions)
                Section("Patients") {
                    ForEach(filteredPatientsSidebar) { p in
                        Button {
                            store.selectedPatientID = p.id
                        } label: {
                            patientRowInline(p)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 6) Add Patient (keep close to list)
                Section {
                    Button { addPatient() } label: {
                        Label("Add Patient", systemImage: "person.badge.plus")
                    }
                }
            }
            .listStyle(.sidebar)

            // 7) Backup & Restore at VERY bottom (outside List)
            Spacer(minLength: 12)

            Button { showBackupCenter = true } label: {
                Label("Backup & Restore", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Sidebar filtering

    private var filteredPatientsSidebar: [Patient] {
        // Start from non-deleted
        var base = store.patients.filter { !$0.isDeleted }

        // Optional: filter by clinic/inpatient scope IF you have a field.
        // If you don't have that field yet, leave this off.
        // Example if you later add patient.isInpatient Bool:
        // switch censusScope {
        // case .clinic:    base = base.filter { !$0.isInpatient }
        // case .inpatient: base = base.filter { $0.isInpatient }
        // }

        // Search
        let q = patientSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            let qq = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            func norm(_ s: String) -> String {
                s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            }

            base = base.filter { p in
                norm(p.nameEnglish).contains(qq) ||
                norm(p.nameArabic).contains(qq) ||
                norm(p.mrn).contains(qq) ||
                norm(p.phone).contains(qq)
            }
        }

        // Sort: updated desc (or name)
        base.sort { $0.updatedAt > $1.updatedAt }
        return base
    }

    // MARK: - Inline patient row (replaces missing PatientRow)

    @ViewBuilder
    private func patientRowInline(_ p: Patient) -> some View {
        let isSelected = (store.selectedPatientID == p.id)

        VStack(alignment: .leading, spacing: 4) {
            Text(displayName(p))
                .font(.headline)
                .foregroundStyle(isSelected ? .blue : .primary)

            HStack(spacing: 8) {
                if !p.mrn.isEmpty {
                    Text("MRN: \(p.mrn)")
                }
                if !p.phone.isEmpty {
                    Text("Phone: \(p.phone)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color(.systemGray5) : Color.clear)
        )
    }

    private func displayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }
    // MARK: - Filtering

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
                let has = store.notes.contains(where: { $0.patientID == p.id && !$0.isDeleted })
                if !has { return false }
            }
            if filterHasImaging {
                let has = store.attachments.contains(where: { $0.patientID == p.id && $0.category == .radiology })
                if !has { return false }
            }
            return true
        }

        // NOTE: censusScope is currently UI-only unless you add a patient flag like `isInpatient`.
        // When you add it, filter here.

        guard !q.isEmpty else {
            return candidates.sorted { patientDisplayName($0) < patientDisplayName($1) }
        }

        return candidates.filter { p in
            let hay = [
                p.nameEnglish, p.nameArabic, p.mrn, p.phone, p.nationalID, p.passport, p.email,
                p.dob.formatted(date: .abbreviated, time: .omitted),
                p.dob.formatted(date: .numeric, time: .omitted),
                String(p.dob.ISO8601Format().prefix(10))
            ]
            .joined(separator: " ")
            .lowercased()

            return hay.contains(q)
        }
        .sorted { patientDisplayName($0) < patientDisplayName($1) }
    }

    // MARK: - Display

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

        parts.append("DOB: \(p.dob.formatted(date: .abbreviated, time: .omitted))")

        let phone = p.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty { parts.append("Phone: \(phone)") }

        return parts.joined(separator: "  •  ")
    }

    // MARK: - Actions

    private func addPatient() {
        var p = Patient()
        p.createdAt = Date()
        p.updatedAt = Date()
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

    private func savePatientEdits(id: UUID) {
        guard let idx = store.patients.firstIndex(where: { $0.id == id }) else { return }
        store.patients[idx].updatedAt = Date()
        store.savePatients()
    }

    private func syncHeaderContext() {
        store.treatingPhysicianName = physicians.selectedPhysicianName?.isEmpty == false
        ? (physicians.selectedPhysicianName ?? "Treating Physician")
        : "Treating Physician"

        store.clinicName = (censusScope == .clinic) ? "Clinic" : "Inpatient"
    }
}

// MARK: - Patient detail host


// MARK: - Patient detail host

import SwiftUI
import Combine

struct PatientDetailHost: View {

    @EnvironmentObject private var store: EMRStore

    @Binding var patient: Patient

    let onSaveAndNewPatient: () -> Void
    let onRequestDelete: () -> Void
    let onPrintDemographics: () -> Void

    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 10) {

            Picker("", selection: $tab) {
                Text("Demographics").tag(0)
                Text("Medical Records").tag(1)
                Text("Clinic Schedule").tag(2)
                Text("References").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            PatientHeaderCard(patient: patient)
                .padding(.horizontal)

            Group {
                switch tab {
                case 0:
                    PatientDemographicsView(
                        patient: $patient,
                        onSaveAndNew: onSaveAndNewPatient,
                        onRequestDelete: onRequestDelete,
                        onPrint: onPrintDemographics
                    )

                case 1:
                    RecordsWorkspaceView(patient: patient)

                case 2:
                    ClinicScheduleView(patient: patient)

                default:
                    ReferencesCenterView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMedicalRecordsTab)) { _ in
            tab = 1
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
// MARK: - Patient header card (compact demographics)

private struct PatientHeaderCard: View {
    let patient: Patient

    private var displayName: String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }

    private var ageYears: Int {
        let comps = Calendar.current.dateComponents([.year], from: patient.dob, to: Date())
        return max(0, comps.year ?? 0)
    }

    private func line(_ label: String, _ value: String) -> String {
        // UI display with 2 spaces after colon (your preference)
        "\(label):  \(value)"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)

                HStack(spacing: 10) {
                    let mrn = patient.mrn.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !mrn.isEmpty {
                        Text(line("MRN", mrn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(line("DOB", patient.dob.formatted(date: .abbreviated, time: .omitted)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(line("Age", "\(ageYears)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack(spacing: 10) {
                    let phone = patient.phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !phone.isEmpty {
                        Text(line("Phone", phone))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(line("Sex", patient.gender.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Clinic/Inpatient UI

private enum CensusScope: String, CaseIterable, Identifiable {
    case clinic = "Clinic"
    case inpatient = "Inpatient"
    var id: String { rawValue }
}

private struct ClinicInpatientCard: View {
    @Binding var scope: CensusScope

    var body: some View {
        GroupBox {
            Picker("", selection: $scope) {
                ForEach(CensusScope.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Search row

private struct PatientSearchRow: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search name, MRN, DOB, phone, ID…", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
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

            Toggle(isOn: $hasNotes) {
                Text("Has notes")
            }

            Toggle(isOn: $hasImaging) {
                Text("Has imaging")
            }
        }
    }

    private func chipLabel(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}
