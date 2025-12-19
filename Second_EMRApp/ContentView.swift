import SwiftUI
import UIKit

struct ContentView: View {

    // MARK: - Stores
    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()
    @StateObject private var backupCenter = BackupCenter()

    // MARK: - UI State
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var searchText = ""
    @State private var tab: WorkspaceTab = .demographics

    @State private var showPhysiciansManager = false
    @State private var confirmDeleteID: UUID?

    // iPhone “Patient Sheet” (Demographics + Records)
    @State private var showPatientSheet = false
    @State private var editingPatientID: UUID?

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        var id: String { rawValue }
    }

    // MARK: - Helpers

    private var isPhoneLayout: Bool { hSize == .compact }

    private var activePatients: [Patient] {
        let base = store.patients.filter { !$0.isDeleted }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let q = trimmed.lowercased()

        return base.filter {
            $0.nameEnglish.lowercased().contains(q) ||
            $0.nameArabic.lowercased().contains(q) ||
            $0.mrn.lowercased().contains(q)
        }
    }

    private var selectedPatientIndex: Int? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.firstIndex(where: { $0.id == id })
    }

    private func bindingForPatient(id: UUID) -> Binding<Patient>? {
        guard let idx = store.patients.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.patients[idx] },
            set: { store.patients[idx] = $0 }
        )
    }

    private func openPatient(_ id: UUID, defaultTab: WorkspaceTab = .demographics) {
        store.selectedPatientID = id
        tab = defaultTab

        if isPhoneLayout {
            editingPatientID = id
            showPatientSheet = true
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .environmentObject(store)
        .environmentObject(physicians)
        .environmentObject(backupCenter)

        // ✅ Wire automatic backup
        .onAppear {
            store.backupCenter = backupCenter
        }

        // Physicians manager
        .sheet(isPresented: $showPhysiciansManager) {
            NavigationStack {
                PhysiciansManagerView()
                    .environmentObject(physicians)
                    .navigationTitle("Physicians")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showPhysiciansManager = false }
                        }
                    }
            }
        }

        // ✅ iPhone patient sheet (Demographics + Medical Records)
        .sheet(isPresented: $showPatientSheet) {
            patientSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }

        // Delete confirmation
        .alert("Delete Patient?", isPresented: Binding(
            get: { confirmDeleteID != nil },
            set: { if !$0 { confirmDeleteID = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDeleteID = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    store.softDeletePatient(id)

                    // If iPhone sheet was showing this patient, close it
                    if isPhoneLayout, editingPatientID == id {
                        showPatientSheet = false
                        editingPatientID = nil
                    }
                }
                confirmDeleteID = nil
            }
        } message: {
            Text("This patient will be removed from the active list.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        NavigationStack {
            VStack(spacing: 12) {

                AttendingPhysicianCard {
                    showPhysiciansManager = true
                }

                BackupInlineCard()

                List {
                    Section("Patients") {
                        ForEach(activePatients) { p in
                            Button {
                                openPatient(p.id, defaultTab: .demographics)
                            } label: {
                                HStack {
                                    Text(p.nameEnglish.isEmpty ? "Unnamed" : p.nameEnglish)
                                    Spacer()
                                    if store.selectedPatientID == p.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    confirmDeleteID = p.id
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    openPatient(p.id, defaultTab: .demographics)
                                } label: {
                                    Label("Edit Demographics", systemImage: "square.and.pencil")
                                }

                                Button {
                                    openPatient(p.id, defaultTab: .records)
                                } label: {
                                    Label("Open Medical Records", systemImage: "doc.text.magnifyingglass")
                                }
                            }
                        }

                        Button {
                            let newPatient = store.addNewPatient()
                            openPatient(newPatient.id, defaultTab: .demographics)
                        } label: {
                            Label("Add Patient", systemImage: "person.badge.plus")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Neurosurgery EMR")
            .searchable(text: $searchText)
        }
    }

    // MARK: - Detail (iPad)

    private var detail: some View {
        Group {
            if let index = selectedPatientIndex {
                VStack(spacing: 12) {

                    Picker("", selection: $tab) {
                        ForEach(WorkspaceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    .zIndex(1)

                    Group {
                        switch tab {
                        case .demographics:
                            PatientDemographicsView(
                                patient: Binding(
                                    get: { store.patients[index] },
                                    set: { store.patients[index] = $0 }
                                ),
                                onSave: {
                                    store.savePatient(store.patients[index])
                                },
                                onRequestDelete: {
                                    confirmDeleteID = store.patients[index].id
                                }
                            )

                        case .records:
                            RecordsWorkspaceView(
                                store: store,
                                patientID: store.patients[index].id,
                                patient: store.patients[index]
                            )
                            .id(store.patients[index].id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                .navigationTitle(tab.rawValue)
                .navigationBarBackButtonHidden(true)

            } else {
                ContentUnavailableView(
                    "No Patient Selected",
                    systemImage: "person.text.rectangle",
                    description: Text("Add a patient, then select them from the sidebar.")
                )
            }
        }
    }

    // MARK: - iPhone Patient Sheet (Demographics + Records)

    private var patientSheet: some View {
        NavigationStack {
            if let id = editingPatientID,
               let binding = bindingForPatient(id: id),
               let idx = store.patients.firstIndex(where: { $0.id == id }) {

                VStack(spacing: 12) {

                    Picker("", selection: $tab) {
                        ForEach(WorkspaceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    Group {
                        switch tab {
                        case .demographics:
                            PatientDemographicsView(
                                patient: binding,
                                onSave: {
                                    store.savePatient(binding.wrappedValue)
                                    showPatientSheet = false
                                },
                                onRequestDelete: {
                                    confirmDeleteID = id
                                    showPatientSheet = false
                                }
                            )

                        case .records:
                            RecordsWorkspaceView(
                                store: store,
                                patientID: store.patients[idx].id,
                                patient: store.patients[idx]
                            )
                            .id(store.patients[idx].id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                .navigationTitle(store.patients[idx].nameEnglish.isEmpty ? "Patient" : store.patients[idx].nameEnglish)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { showPatientSheet = false }
                    }
                }

            } else {
                Text("No patient selected.")
                    .padding()
                    .navigationTitle("Patient")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { showPatientSheet = false }
                        }
                    }
            }
        }
    }
}
