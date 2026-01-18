import SwiftUI

struct ContentView: View {

    // MARK: - Environment
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    // MARK: - Sheets
   
    @State private var showPhysiciansManager = false
    @State private var showBackupCenter = false

    private enum WorkspacePane: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        var id: String { rawValue }
    }

    @State private var pane: WorkspacePane = .demographics
    
    // MARK: - New Patient / Switch Patient warnings
    @State private var showPatientDecision = false
    @State private var pendingSelectPatientID: UUID? = nil
    @State private var pendingCreateNewPatient = false

    // MARK: - Derived
    private var selectedPatient: Patient? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.first(where: { $0.id == id && !$0.isDeleted })
    }

    private var filteredPatients: [Patient] {
        let q = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = store.patients.filter { !$0.isDeleted }

        guard !q.isEmpty else { return base }

        let qq = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return base.filter { p in
            let en = p.nameEnglish.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let ar = p.nameArabic.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let mrn = p.mrn.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return en.contains(qq) || ar.contains(qq) || mrn.contains(qq)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showPhysiciansManager) {
            NavigationStack {
                PhysiciansManagerSheetView()
                    .environmentObject(physicians)
            }
        }
        .sheet(isPresented: $showBackupCenter) {
            NavigationStack {
                BackupCenterPlaceholderView()
                    .environmentObject(store)
                    .environmentObject(physicians)
            }
        }
        .confirmationDialog(
            "Current patient has a name",
            isPresented: $showPatientDecision,
            titleVisibility: .visible
        ) {
            Button("Save current & continue") {
                store.savePatients()

                if pendingCreateNewPatient {
                    createNewPatientAndSelect()
                } else if let id = pendingSelectPatientID {
                    store.selectedPatientID = id
                    store.selectedNoteID = nil
                    store.selectedAttachmentID = nil
                    store.selectedVitalID = nil
                }

                pendingCreateNewPatient = false
                pendingSelectPatientID = nil
            }

            Button("Delete current & continue", role: .destructive) {
                softDeleteCurrentPatient()

                if pendingCreateNewPatient {
                    createNewPatientAndSelect()
                } else if let id = pendingSelectPatientID {
                    store.selectedPatientID = id
                    store.selectedNoteID = nil
                    store.selectedAttachmentID = nil
                    store.selectedVitalID = nil
                }

                pendingCreateNewPatient = false
                pendingSelectPatientID = nil
            }

            Button("Cancel", role: .cancel) {
                pendingCreateNewPatient = false
                pendingSelectPatientID = nil
            }
        } message: {
            Text("Do you want to save or delete the current patient before continuing?")
        }
    }

    
    private func currentPatientHasName() -> Bool {
        guard let id = store.selectedPatientID,
              let p = store.patients.first(where: { $0.id == id && !$0.isDeleted })
        else { return false }

        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        return !en.isEmpty || !ar.isEmpty
    }

    private func createNewPatientAndSelect() {
        // If your Patient has a different initializer, adjust here.
        var p = Patient()
        p.createdAt = Date()
        p.updatedAt = Date()

        store.patients.append(p)
        store.savePatients()

        store.selectedPatientID = p.id
        store.selectedNoteID = nil
        store.selectedAttachmentID = nil
        store.selectedVitalID = nil
    }

    private func softDeleteCurrentPatient() {
        guard let id = store.selectedPatientID,
              let idx = store.patients.firstIndex(where: { $0.id == id })
        else { return }

        var p = store.patients[idx]
        p.isDeleted = true
        p.updatedAt = Date()
        store.patients[idx] = p
        store.savePatients()

        // Select next available patient
        store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
        store.selectedNoteID = nil
        store.selectedAttachmentID = nil
        store.selectedVitalID = nil
    }

    private func requestCreateNewPatient() {
        pendingCreateNewPatient = true
        pendingSelectPatientID = nil

        // Your rule: if there is a name already → warn
        if currentPatientHasName() {
            showPatientDecision = true
        } else {
            createNewPatientAndSelect()
            pendingCreateNewPatient = false
        }
    }

    private func requestSelectPatient(_ id: UUID) {
        pendingSelectPatientID = id
        pendingCreateNewPatient = false

        // Warn only if current demographics already has a name
        if currentPatientHasName() {
            showPatientDecision = true
        } else {
            store.selectedPatientID = id
            store.selectedNoteID = nil
            store.selectedAttachmentID = nil
            store.selectedVitalID = nil
            pendingSelectPatientID = nil
        }
    }
    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List {
                Section("Treating Physician") {
                    TreatingPhysicianCard(onManage: {
                        showPhysiciansManager = true
                    })
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }

                Section("Search") {
                    TextField("Search patients", text: $store.searchText)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    if filteredPatients.isEmpty {
                        Text("No patients")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredPatients) { p in
                            Button {
                                requestSelectPatient(p.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.nameEnglish.isEmpty ? "Unnamed" : p.nameEnglish)
                                            .font(.headline)
                                            .lineLimit(1)
                                        if !p.mrn.isEmpty {
                                            Text("MRN: \(p.mrn)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text("Patients")
                        Spacer()
                        Button {
                            requestCreateNewPatient()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add Patient")
                    }
                }
            }
            .listStyle(.sidebar)

            // Bottom bar button (outside list)
            VStack(spacing: 10) {
                Button {
                    showBackupCenter = true
                } label: {
                    Label("Backup & Restore", systemImage: "externaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .navigationTitle("NeuroEMR")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let patient = selectedPatient {
            if let idx = store.patients.firstIndex(where: { $0.id == patient.id }) {

                Group {
                    switch pane {
                    case .demographics:
                        PatientDemographicsView(
                            patient: $store.patients[idx],
                            onSaveAndNew: {
                                // 1) Save edits
                                store.savePatients()

                                // 2) Create a new patient and select it
                                var newP = Patient()
                                newP.createdAt = Date()
                                newP.updatedAt = Date()
                                store.patients.append(newP)
                                store.savePatients()
                                store.selectedPatientID = newP.id

                                // 3) Clear right-pane selections
                                store.selectedNoteID = nil
                                store.selectedAttachmentID = nil
                                store.selectedVitalID = nil
                            },
                            onRequestDelete: {
                                // Soft-delete selected patient
                                let id = store.patients[idx].id
                                var p = store.patients[idx]
                                p.isDeleted = true
                                p.updatedAt = Date()
                                store.patients[idx] = p
                                store.savePatients()

                                // Move selection to next available patient (or nil)
                                let next = store.patients.first(where: { !$0.isDeleted })?.id
                                store.selectedPatientID = next

                                // Clear right-pane selections
                                store.selectedNoteID = nil
                                store.selectedAttachmentID = nil
                                store.selectedVitalID = nil
                            },
                            onPrint: nil
                        )

                    case .records:
                        RecordsWorkspaceView(patient: store.patients[idx])
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("", selection: $pane) {
                            ForEach(WorkspacePane.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)
                    }
                }

            } else {
                ContentUnavailableView("Patient not found", systemImage: "person.crop.circle.badge.questionmark")
            }
        } else {
            ContentUnavailableView("Select a patient", systemImage: "person.text.rectangle")
        }
    }
}

// MARK: - Treating Physician Card

private struct TreatingPhysicianCard: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    @EnvironmentObject private var store: EMRStore   // ✅ FIX: now store is in scope
    let onManage: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Treating Physician")
                        .font(.headline)
                    Spacer()
                    Button("Manage") { onManage() }
                        .font(.subheadline)
                }

                Picker("Treating Physician", selection: $physicians.selectedPhysicianID) {
                    Text("—").tag(UUID?.none)
                    ForEach(physicians.physicians) { p in
                        Text(p.name.isEmpty ? "Unnamed" : p.name)
                            .tag(UUID?.some(p.id))
                    }
                }
                .pickerStyle(.menu)
                .onAppear { syncPhysicianToStore() } // ✅ initial sync
                .onChange(of: physicians.selectedPhysicianID) { _, _ in
                    syncPhysicianToStore()            // ✅ sync whenever selection changes
                }

                if let name = physicians.selectedPhysicianName, !name.isEmpty {
                    Text("Selected: \(name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No physician selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func syncPhysicianToStore() {
        guard let id = physicians.selectedPhysicianID,
              let p = physicians.physicians.first(where: { $0.id == id }) else {
            store.treatingPhysicianName = ""
            store.clinicName = ""
            store.treatingPhysicianPhone = ""
            return
        }

        store.treatingPhysicianName = p.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let clinic = p.clinic.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = p.specialty.trimmingCharacters(in: .whitespacesAndNewlines)
        store.clinicName = !clinic.isEmpty ? clinic : spec

        store.treatingPhysicianPhone = p.contactPhone.trimmingCharacters(in: .whitespacesAndNewlines
           )
        }
    }


// MARK: - Physicians Manager (NO PhysicianEditorView dependency)

private struct PhysiciansManagerSheetView: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    let p = physicians.addPhysician()
                    physicians.selectedPhysicianID = p.id
                } label: {
                    Label("Add Physician", systemImage: "plus")
                }
            }

            Section("Physicians") {
                if physicians.physicians.isEmpty {
                    Text("No physicians yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(physicians.physicians) { p in
                        NavigationLink {
                            PhysicianInlineEditorView(physicianID: p.id)
                                .environmentObject(physicians)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name.isEmpty ? "Unnamed" : p.name)
                                    .font(.headline)
                                if !p.specialty.isEmpty {
                                    Text(p.specialty)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idxSet in
                        for i in idxSet {
                            let id = physicians.physicians[i].id
                            physicians.deletePhysician(id: id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Physicians")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

private struct PhysicianInlineEditorView: View {
    @EnvironmentObject private var physicians: PhysiciansStore
    let physicianID: UUID

    private var index: Int? {
        physicians.physicians.firstIndex(where: { $0.id == physicianID })
    }

    var body: some View {
        if let idx = index {
            Form {
                Section("Basics") {
                    TextField("Name", text: binding(\.name, idx))
                    TextField("Specialty", text: binding(\.specialty, idx))
                    TextField("Clinic", text: binding(\.clinic, idx))
                }

                Section("Contact") {
                    TextField("License Number", text: binding(\.licenseNumber, idx))
                    TextField("Phone", text: binding(\.contactPhone, idx))
                    TextField("Email", text: binding(\.contactEmail, idx))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Physician")
            .onDisappear {
                physicians.save()
            }
        } else {
            ContentUnavailableView("Physician not found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func binding(_ kp: WritableKeyPath<Physician, String>, _ idx: Int) -> Binding<String> {
        Binding(
            get: { physicians.physicians[idx][keyPath: kp] },
            set: { newValue in
                physicians.physicians[idx][keyPath: kp] = newValue
                physicians.save()
            }
        )
    }
}

// MARK: - Backup placeholder

private struct BackupCenterPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Backup & Restore")
                .font(.title2).bold()

            Text("Placeholder screen so the Backup button works.\nPaste your BackupCenterView.swift anytime and I’ll reconnect it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
