//
//  ContentView.swift
//  Second_EMRApp
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore

    @Environment(\.horizontalSizeClass) private var hSize
    private var isPhone: Bool { hSize == .compact }

    // MARK: - Tabs (detail)
    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case demographics = "Demographics"
        case records = "Medical Records"
        var id: String { rawValue }
    }

    @State private var tab: WorkspaceTab = .demographics

    // MARK: - Delete UI
    @State private var confirmDeletePatientID: UUID? = nil

    // MARK: - Selected patient helpers
    private var selectedPatientIndex: Int? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.firstIndex(where: { $0.id == id })
    }

    private var selectedPatient: Patient? {
        guard let idx = selectedPatientIndex else { return nil }
        return store.patients[idx]
    }

    // MARK: - Body
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

            // If you have your own attending physician / backup views, you can re-add them here.
            // Keeping sidebar clean for stability.

            Section("Patients") {
                ForEach(store.patients) { p in
                    Text(patientDisplayName(p))
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    addPatient()
                } label: {
                    Image(systemName: "plus")
                }

                Button(role: .destructive) {
                    if let id = store.selectedPatientID {
                        confirmDeletePatientID = id
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(store.selectedPatientID == nil)
            }
        }
        .alert("Delete patient?", isPresented: Binding(
            get: { confirmDeletePatientID != nil },
            set: { if !$0 { confirmDeletePatientID = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDeletePatientID = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmDeletePatientID {
                    deletePatient(id)
                }
                confirmDeletePatientID = nil
            }
        } message: {
            Text("This will remove the patient and their data from this device.")
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let idx = selectedPatientIndex {
                let p = store.patients[idx]

                VStack(spacing: 12) {

                    Picker("", selection: $tab) {
                        ForEach(WorkspaceTab.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 6)
                    .padding(.horizontal)

                    Group {
                        switch tab {
                        case .demographics:
                            PatientDemographicsView(
                                patient: Binding(
                                    get: { store.patients[idx] },
                                    set: { store.patients[idx] = $0 }
                                ),
                                onSave: {
                                    store.lastModified = Date()
                                    // If you have a savePatient() method, call it here.
                                    // store.savePatient(store.patients[idx])
                                },
                                onRequestDelete: {
                                    confirmDeletePatientID = store.patients[idx].id
                                }
                            )
                            .padding(.horizontal)

                        case .records:
                            RecordsWorkspaceView(patient: p)
                                .padding(.horizontal, isPhone ? 0 : 8)
                                .id(p.id) // helps refresh when switching patients
                        }
                    }
                }
                .navigationTitle(patientDisplayName(p))
                .navigationBarTitleDisplayMode(.inline)

            } else {
                ContentUnavailableView("Select a patient", systemImage: "person.text.rectangle")
            }
        }
    }

    // MARK: - Actions

    private func addPatient() {
        // Create the simplest patient your model allows.
        // If your Patient has a different initializer, adjust here.

        var p = Patient()
        // If your Patient() init doesn’t exist, replace with your real init.
        // Example:
        // var p = Patient(nameEnglish: "", nameArabic: "", gender: .male, dob: Date(), mrn: "", nationalID: "", passport: "", phone: "")

        store.patients.append(p)
        store.selectedPatientID = p.id
        store.lastModified = Date()
    }

    private func deletePatient(_ id: UUID) {
        store.patients.removeAll(where: { $0.id == id })
        if store.selectedPatientID == id {
            store.selectedPatientID = store.patients.first?.id
        }
        store.lastModified = Date()
    }

    // MARK: - Display

    private func patientDisplayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ar.isEmpty { return ar }
        return "Patient"
    }
}
