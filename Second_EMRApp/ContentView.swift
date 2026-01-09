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

            // Optional inline references card (you said you already have it)
            Section {
                ReferencesInlineCard(onOpen: { showReferenceCenter = true })
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            } header: {
                Text("References")
            }

            // Filters (chips)
            Section {
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

                        // Name line (highlight match)
                        highlightText(
                            patientDisplayName(p),
                            query: patientSearchText
                        )
                        .font(.headline)

                        // Secondary line (MRN / Phone / DOB) - also searchable
                        let secondary = patientSecondaryLine(p)
                        if !secondary.isEmpty {
                            highlightText(secondary, query: patientSearchText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(p.id as UUID?)
                }

                Button {
                    addPatient()
                } label: {
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
            ReferenceCenterView()
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalRecordSearchView()
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
                    onSavePatient: { savePatientEdits(id: id) },
                    onRequestDelete: { confirmDeletePatientID = id }
                )

            } else {
                ContentUnavailableView("Select a patient", systemImage: "person")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Patient Filtering + Ranking

    private var filteredPatientsForSidebar: [Patient] {
        let q = patientSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Base set: not deleted
        var candidates = store.patients.filter { !$0.isDeleted }

        // Apply filter chips
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
                // “Has Imaging” == has any Radiology attachment
                let has = store.attachments.contains(where: { $0.patientID == p.id && $0.category == .radiology })
                if !has { return false }
            }
            return true
        }

        // No search text => just sort by name
        guard !q.isEmpty else {
            return candidates.sorted { patientDisplayName($0) < patientDisplayName($1) }
        }

        // Ranked search
        return candidates
            .map { p -> (Patient, Int) in
                (p, patientMatchScore(p, query: q))
            }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return patientDisplayName(a.0) < patientDisplayName(b.0)
            }
            .map { $0.0 }
    }

    private func patientMatchScore(_ p: Patient, query q: String) -> Int {
        // Higher = better
        // 1) Name hits first
        // 2) MRN next
        // 3) DOB next
        // 4) then phone / IDs / email
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

        // Bonus for prefix match (feels “smarter”)
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

        return parts.joined(separator: "  •  ")
    }

    // Simple highlight: if query exists in full string, make the whole text slightly emphasized.
    // (Safer than substring attribute slicing which can crash on index math in SwiftUI.)
    private func highlightText(_ text: String, query: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Text(text) }
        if text.lowercased().contains(q) {
            return Text(text).bold()
        } else {
            return Text(text)
        }
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

        // select another available patient
        store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
    }

    private func savePatientEdits(id: UUID) {
        guard let idx = store.patients.firstIndex(where: { $0.id == id }) else { return }
        store.patients[idx].updatedAt = Date()
        store.savePatients()
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
                    // Your PatientDemographicsView requires closures (per your error)
                    PatientDemographicsView(
                        patient: $patient,
                        onSave: {  onSavePatient() },
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
                Toggle(isOn: $hasNotes) {
                    chipLabel("Has Notes")
                }
                .toggleStyle(.button)

                Toggle(isOn: $hasImaging) {
                    chipLabel("Has Imaging")
                }
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

// MARK: - Global Search (all notes + all attachments across all patients)

private struct GlobalRecordSearchView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: EMRStore

    @State private var q: String = ""

    private var matchedNotes: [RecordNote] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return store.notes.filter { (n: RecordNote) in
            let hay = [
                n.displayTitle,
                n.type.rawValue,
                n.body
            ].joined(separator: " ").lowercased()
            return hay.contains(query)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var matchedAttachments: [Attachment] {
        let query = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        return store.attachments.filter { (a: Attachment) in
            let hay = [
                a.category.rawValue,
                a.originalFileName,
                a.storedFileName
            ].joined(separator: " ").lowercased()
            return hay.contains(query)
        }
        .sorted { $0.originalFileName.localizedCaseInsensitiveCompare($1.originalFileName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {

                if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Search records", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {

                    if !matchedNotes.isEmpty {
                        Section("Notes") {
                            ForEach(matchedNotes) { n in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(noteTitle(n))
                                        .font(.headline)
                                    Text(patientName(n.patientID))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !matchedAttachments.isEmpty {
                        Section("Attachments") {
                            ForEach(matchedAttachments) { a in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(a.originalFileName)
                                        .font(.headline)
                                    Text("\(patientName(a.patientID)) • \(a.category.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if matchedNotes.isEmpty && matchedAttachments.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Global Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $q, prompt: "Search notes + attachments")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func patientName(_ patientID: UUID) -> String {
        guard let p = store.patients.first(where: { $0.id == patientID }) else { return "Unknown patient" }
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }

    private func noteTitle(_ n: RecordNote) -> String {
        let t = n.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Clinical Note" : t
    }
}

// MARK: - Minimal Reference Center (so ReferencesInlineCard compiles)

private struct ReferenceCenterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("Reference Center")
                    .font(.headline)
                Text("You can build your reference content here (GCS, Hunt/Hess, Fisher, etc.).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("References")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Date helper

private extension Date {
    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0
    }
}
