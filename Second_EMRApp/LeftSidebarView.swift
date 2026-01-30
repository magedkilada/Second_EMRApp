import SwiftUI

struct LeftSidebarView: View {
    @EnvironmentObject private var store: EMRStore
    @EnvironmentObject private var physicians: PhysiciansStore
    @EnvironmentObject private var backupCenter: BackupCenter

    @Binding var searchText: String

    // Sheets
    @State private var showPhysiciansManager = false
    @State private var showBackupRestore = false
    @State private var showAddPatient = false

    // Soft-delete confirmations
    @State private var confirmDeletePatientID: UUID? = nil
    @State private var showDeletePhysicianAlert = false
    @State private var showCannotDeletePatientAlert = false
    @State private var cannotDeletePatientName = ""
    @State private var cannotDeleteNoteCount = 0

    // Local state for new patient sheet
    @State private var newPatient = Patient()
    @State private var showScheduleForPatient: Patient?

    private var selectedPatient: Patient? {
        guard let id = store.selectedPatientID else { return nil }
        return store.patients.first(where: { $0.id == id })
    }

    private var filteredPatients: [Patient] {
        let active = store.patients.filter { !$0.isDeleted }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return active }

        let lower = q.lowercased()
        return active.filter { p in
            p.nameEnglish.lowercased().contains(lower) ||
            p.nameArabic.contains(q) ||
            p.mrn.contains(q) ||
            p.nationalID.contains(q) ||
            p.phone.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Backup card
                    backupCard
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // 2. Physician card with edit/delete
                    physicianCard
                        .padding(.horizontal)

                    // 3. Add Patient button
                    addPatientButton
                        .padding(.horizontal)

                    // 4. Smart search
                    smartSearchField
                        .padding(.horizontal)

                    // 5. Patient list
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Patients (\(filteredPatients.count))")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(filteredPatients) { patient in
                            PatientRowButton(
                                patient: patient,
                                isSelected: patient.id == store.selectedPatientID,
                                onTap: {
                                    store.selectedPatientID = patient.id
                                },
                                onDelete: {
                                    attemptDeletePatient(patient)
                                },
                                onSchedule: {
                                    showScheduleForPatient = patient
                                }
                            )
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("EMR")
        .sheet(isPresented: $showPhysiciansManager) {
            PhysiciansManagerView()
                .environmentObject(physicians)
        }
        .sheet(isPresented: $showBackupRestore) {
            BackupRestoreView()
                .environmentObject(store)
                .environmentObject(backupCenter)
        }
        .sheet(isPresented: $showAddPatient, onDismiss: {
            newPatient = Patient()
        }) {
            NavigationStack {
                PatientDemographicsView(
                    patient: $newPatient,
                    onSave: {
                        var p = newPatient
                        p.updatedAt = Date()
                        store.savePatient(p)
                        store.selectedPatientID = p.id
                        showAddPatient = false
                    },
                    onRequestDelete: {
                        showAddPatient = false
                    }
                )
                .environmentObject(store)
                .navigationTitle("New Patient")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddPatient = false }
                    }
                }
            }
        }
        .confirmationDialog(
            "Soft Delete Patient?",
            isPresented: Binding(
                get: { confirmDeletePatientID != nil },
                set: { if !$0 { confirmDeletePatientID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Patient (Soft)", role: .destructive) {
                if let id = confirmDeletePatientID {
                    store.softDeletePatient(id)
                }
                confirmDeletePatientID = nil
            }
            Button("Cancel", role: .cancel) {
                confirmDeletePatientID = nil
            }
        } message: {
            Text("This will soft-delete the patient (reversible via restore / future undo).")
        }
        .alert("Cannot Delete Patient", isPresented: $showCannotDeletePatientAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(cannotDeletePatientName) has \(cannotDeleteNoteCount) medical record(s). Please delete all medical records before deleting the patient.")
        }
        .sheet(item: $showScheduleForPatient) { patient in
            ScheduleView()
                .environmentObject(store)
        }
        .alert("Soft Delete Physician?", isPresented: $showDeletePhysicianAlert) {
            Button("Delete", role: .destructive) {
                if let id = physicians.selectedPhysicianID {
                    physicians.softDelete(id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will soft-delete the physician entry.")
        }
    }

    // MARK: - Delete Protection

    private func attemptDeletePatient(_ patient: Patient) {
        let records = store.recordsForPatient(patient.id)
        if records.isEmpty {
            confirmDeletePatientID = patient.id
        } else {
            cannotDeletePatientName = patient.nameEnglish.isEmpty ? "This patient" : patient.nameEnglish
            cannotDeleteNoteCount = records.count
            showCannotDeletePatientAlert = true
        }
    }

    // MARK: - Components

    private var backupCard: some View {
        Button {
            showBackupRestore = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup & Restore").font(.headline).foregroundStyle(.primary)
                    Text("Secure clinical data").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondarySystemGroupedBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var physicianCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Physician", systemImage: "stethoscope").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showPhysiciansManager = true } label: {
                    Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button {
                    if physicians.selectedPhysicianID != nil {
                        showDeletePhysicianAlert = true
                    }
                } label: {
                    Image(systemName: "trash.circle.fill").font(.title3).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .disabled(physicians.selectedPhysicianID == nil)
            }

            if let physician = physicians.selectedPhysician {
                VStack(alignment: .leading, spacing: 6) {
                    Text(physician.name).font(.headline)
                    if !physician.specialty.isEmpty {
                        Text(physician.specialty).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !physician.clinic.isEmpty {
                        Label(physician.clinic, systemImage: "building.2").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No physician selected").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var addPatientButton: some View {
        Button { showAddPatient = true } label: {
            HStack {
                Image(systemName: "person.badge.plus").font(.headline)
                Text("Add Patient").font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var smartSearchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Smart search...", text: $searchText)
                .mobileAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.tertiarySystemGroupedBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Patient Row Button Component

struct PatientRowButton: View {
    let patient: Patient
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    var onSchedule: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(patient.nameEnglish.isEmpty ? "Unnamed Patient" : patient.nameEnglish)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .blue : .primary)

                    HStack(spacing: 8) {
                        Label("# \(patient.mrn)", systemImage: "number").font(.caption)
                        Label(patient.gender.rawValue, systemImage: "person").font(.caption)
                        if let age = patient.ageString {
                            Label(age, systemImage: "calendar").font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(6)
                }
                .buttonStyle(.plain)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.secondarySystemGroupedBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onSchedule = onSchedule {
                Button { onSchedule() } label: {
                    Label("Add to Schedule", systemImage: "calendar.badge.plus")
                }
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete (Soft)", systemImage: "trash")
            }
        }
    }
}
