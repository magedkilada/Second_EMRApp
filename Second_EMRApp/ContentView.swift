import SwiftUI

struct ContentView: View {

    // MARK: - Stores
    @StateObject private var store = EMRStore()
    @StateObject private var physicianStore = PhysiciansStore()
    @StateObject private var backupCenter = BackupCenter()
    @State private var showPhysicianCardExpanded: Bool = false
    @State private var showBackupExpanded: Bool = false

    // MARK: - UI State
    @State private var searchText: String = ""
    @State private var tab: WorkspaceTab = .demographics

    @State private var showPhysiciansManager = false
    @State private var showRestoreConfirm = false
    @State private var showBackupDone = false

    @State private var confirmDeletePatientID: UUID? = nil

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .onAppear {
            if store.selectedPatientID == nil {
                store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
            }
            backupCenter.configureIfNeeded()
        }
        .sheet(isPresented: $showPhysiciansManager) {
            PhysiciansManagerView()
                .environmentObject(physicianStore)
        }
        .alert("Delete patient?", isPresented: Binding(
            get: { confirmDeletePatientID != nil },
            set: { if !$0 { confirmDeletePatientID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeletePatientID {
                    store.deletePatient(id: id)
                    if store.selectedPatientID == id {
                        store.selectedPatientID = store.patients.first(where: { !$0.isDeleted })?.id
                    }
                }
                confirmDeletePatientID = nil
            }
            Button("Cancel", role: .cancel) { confirmDeletePatientID = nil }
        } message: {
            Text("This will permanently delete this patient.")
        }
        .alert("Restore backup?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) {
                if let restored = backupCenter.restoreLatest() {
                    store.patients = restored
                    store.selectedPatientID = restored.first(where: { !$0.isDeleted })?.id
                    tab = .demographics
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will replace your current patients list with the backup data.")
        }
        .alert("Backup complete", isPresented: $showBackupDone) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your encrypted patients backup was saved.")
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        List {
            ForEach(filteredPatients) { p in
                Button {
                    store.selectedPatientID = p.id
                    tab = .demographics   // ✅ always show Demographics after selecting a patient
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName(for: p))
                                .font(.headline)

                            if !p.mrn.isEmpty {
                                Text("MRN: \(p.mrn)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        if store.selectedPatientID == p.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        confirmDeletePatientID = p.id
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
                    tab = .demographics
                } label: {
                    Label("Add Patient", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Detail
    private var detailPane: some View {
        NavigationStack {
            if let id = store.selectedPatientID,
               let patientBinding = store.patientBinding(for: id) {

                VStack(spacing: 8) {

                    Picker("", selection: $tab) {
                        ForEach(WorkspaceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    switch tab {

                    case .demographics:
                        VStack(spacing: 6) {

                            // Collapsible Attending Physician
                            DisclosureGroup(
                                isExpanded: $showPhysicianCardExpanded,
                                content: {
                                    AttendingPhysicianCard(onManage: {
                                        showPhysiciansManager = true
                                    })
                                    .environmentObject(physicianStore)
                                    .padding(.top, 4)
                                },
                                label: {
                                    HStack {
                                        Text("Attending Physician")
                                            .font(.subheadline).bold()
                                        Spacer()
                                        Image(systemName: showPhysicianCardExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 12)

                            // Collapsible Backup
                            DisclosureGroup(
                                isExpanded: $showBackupExpanded,
                                content: {
                                    BackupInlineCard(
                                        onBackupNow: {
                                            backupCenter.configureIfNeeded()
                                            backupCenter.backupNow(patients: store.patients)
                                            if backupCenter.lastErrorMessage == nil { showBackupDone = true }
                                        },
                                        onRestore: { showRestoreConfirm = true }
                                    )
                                    .environmentObject(backupCenter)
                                    .padding(.top, 4)
                                },
                                label: {
                                    HStack {
                                        Text("Backup")
                                            .font(.subheadline).bold()
                                        Spacer()
                                        Image(systemName: showBackupExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 12)

                            // Full Demographics form (normal, fast entry)
                            PatientDemographicsView(
                                patient: patientBinding,
                                onSave: { store.savePatient(id: id) },
                                onRequestDelete: { confirmDeletePatientID = id }
                            )
                            .safeAreaInset(edge: .bottom) {
                                HStack(spacing: 10) {
                                    Button { store.savePatient(id: id) } label: {
                                        Label("Save", systemImage: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button(role: .destructive) { confirmDeletePatientID = id } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                            }
                        }

                    case .records:
                        RecordsWorkspaceView()
                    }
                }
                .navigationTitle(tab.rawValue)
                .navigationBarTitleDisplayMode(.inline)

            } else {
                ContentUnavailableView(
                    "No Patient Selected",
                    systemImage: "person.text.rectangle",
                    description: Text("Add a patient, then select them from the list.")
                )
                .navigationTitle("Demographics")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    // MARK: - Helpers
    private func displayName(for p: Patient) -> String {
        let n = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Unnamed (English)" : n
    }

    private var filteredPatients: [Patient] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let alive = store.patients.filter { !$0.isDeleted }
        guard !q.isEmpty else { return alive }

        return alive.filter { p in
            p.nameEnglish.lowercased().contains(q) ||
            p.nameArabic.lowercased().contains(q) ||
            p.mrn.lowercased().contains(q) ||
            p.phone.lowercased().contains(q)
        }
    }
}
