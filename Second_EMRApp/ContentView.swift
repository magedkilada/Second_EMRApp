import SwiftUI
import UIKit

struct ContentView: View {
    
    // MARK: - Stores
    @StateObject private var store = EMRStore()
    @StateObject private var physicians = PhysiciansStore()
    @StateObject private var backupCenter = BackupCenter()
    
    // MARK: - UI State
    @State private var searchText = ""
    @State private var tab: WorkspaceTab = .demographics
    @State private var showPhysiciansManager = false
    @State private var confirmDeleteID: UUID?
    
    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .environmentObject(store)
        .environmentObject(physicians)
        .environmentObject(backupCenter)
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
        .alert("Delete Patient?", isPresented: Binding(
            get: { confirmDeleteID != nil },
            set: { if !$0 { confirmDeleteID = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDeleteID = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    store.softDeletePatient(id)
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
                
                BackupInlineCard(
                    onBackupNow: {
                        backupCenter.backupNow(patients: store.patients)
                    },
                    onRestore: {
                        if let restored = backupCenter.restoreLatest() {
                            store.patients = restored
                            store.selectedPatientID = restored.first(where: { !$0.isDeleted })?.id
                        }
                    }
                )
                
                List {
                    Section("Patients") {
                        ForEach(activePatients) { p in
                            Button {
                                store.selectedPatientID = p.id
                                tab = .demographics
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
                            }
                        }
                        
                        Button {
                            store.addNewPatient()
                            tab = .demographics
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
    
    private var activePatients: [Patient] {
        store.patients.filter { !$0.isDeleted }
    }
    
    // MARK: - Detail
    
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
                            .id(store.patients[index].id) // important when switching patients
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
    
    private var selectedPatientIndex: Int? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.firstIndex(where: { $0.id == id })
    }
}
