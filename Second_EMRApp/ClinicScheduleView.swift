import SwiftUI

struct ClinicScheduleView: View {

    let patient: Patient

    @EnvironmentObject private var store: EMRStore

    @State private var day: Date = Date()
    @State private var showNeedClinicAlert = false
    @State private var pendingSlotToAssign: Date? = nil
    @State private var showSlotTakenAlert = false

    var body: some View {
        VStack(spacing: 0) {

            header

            Divider()

            List {
                Section {
                    ForEach(ClinicSchedule.timeSlots(for: day), id: \.self) { slot in
                        slotRow(slot)
                    }
                } header: {
                    Text("Time Slots (10:00–22:00)")
                }
            }
        }
        .navigationTitle("Clinic Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Switch to Clinic?", isPresented: $showNeedClinicAlert) {
            Button("Cancel", role: .cancel) {
                pendingSlotToAssign = nil
            }
            Button("Switch & Assign") {
                if let slot = pendingSlotToAssign {
                    assignSelectedPatient(to: slot, forceClinic: true)
                }
                pendingSlotToAssign = nil
            }
        } message: {
            Text("The selected patient is currently marked as Inpatient. Switch to Clinic and assign this appointment time?")
        }
        .alert("Slot already taken", isPresented: $showSlotTakenAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This time slot is already assigned to another patient. Remove them from the schedule first, then assign.")
        }
        .alert("Remove from schedule?", isPresented: $showRemoveFromScheduleAlert) {
            Button("Cancel", role: .cancel) {
                pendingRemovePatientID = nil
            }
            Button("Remove", role: .destructive) {
                if let pid = pendingRemovePatientID {
                    removeFromSchedule(patientID: pid)
                }
            }
        } message: {
            Text("This removes the appointment only. Patient demographics will NOT be deleted.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {

            Button {
                day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            DatePicker(
                "",
                selection: $day,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Spacer()

            Button {
                day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Slot row

    // MARK: - Slot Row

    @ViewBuilder
    private func slotRow(_ slot: Date) -> some View {

        if let assigned = patientAssigned(to: slot) {

            Button {
                // 1) Select that patient in the app
                store.selectedPatientID = assigned.id

                // 2) Jump to Medical Records tab
                NotificationCenter.default.post(name: .openMedicalRecordsTab, object: nil)

            } label: {
                HStack(spacing: 12) {
                    Text(slot.formatted(date: .omitted, time: .shortened))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(width: 90, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName(for: assigned))
                            .font(.headline)
                            .lineLimit(1)

                        Text("Tap to open Medical Records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    requestRemoveFromSchedule(patientID: assigned.id)
                } label: {
                    Label("Remove from schedule", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    requestRemoveFromSchedule(patientID: assigned.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }

        } else {

            Button {
                requestAssign(slot: slot)
            } label: {
                HStack(spacing: 12) {
                    Text(slot.formatted(date: .omitted, time: .shortened))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(width: 90, alignment: .leading)

                    Text("Available")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func displayName(for patient: Patient) -> String {
        let en = patient.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = patient.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }
    // MARK: - Assign flow

    @State private var showRemoveFromScheduleAlert: Bool = false
    @State private var pendingRemovePatientID: UUID? = nil

    private func requestAssign(slot: Date) {
        // Prevent double-booking
        if patientAssigned(to: slot) != nil {
            showSlotTakenAlert = true
            return
        }

        if needsClinicSwitch() {
            pendingSlotToAssign = slot
            showNeedClinicAlert = true
        } else {
            assignSelectedPatient(to: slot, forceClinic: false)
        }
    }

    private func assignSelectedPatient(to slot: Date, forceClinic: Bool) {
        // If you want to actually flip patient to “Clinic” mode,
        // do it inside setClinicModeIfNeeded(forceClinic:)
        setClinicModeIfNeeded(forceClinic: forceClinic)

        // ✅ Persist appointment into your patient model
        guard let idx = store.patients.firstIndex(where: { $0.id == patient.id }) else { return }
        store.patients[idx].clinicAppointmentDate = slot
        store.patients[idx].updatedAt = Date()

        // ✅ SAVE immediately (persists after restart)
        store.savePatients()

        // Clear pending
        pendingSlotToAssign = nil
    }

    private func requestRemoveFromSchedule(patientID: UUID) {
        pendingRemovePatientID = patientID
        showRemoveFromScheduleAlert = true
    }

    private func removeFromSchedule(patientID: UUID) {
        guard let idx = store.patients.firstIndex(where: { $0.id == patientID }) else { return }
        store.patients[idx].clinicAppointmentDate = nil
        store.patients[idx].updatedAt = Date()
        store.savePatients()

        pendingRemovePatientID = nil
    }
    // MARK: - Lookup helpers

    private func patientAssigned(to slot: Date) -> Patient? {
        // Match exact slot time (10:00, 10:15, etc.)
        // This assumes you store the exact slot Date into clinicAppointmentDate.
        return store.patients.first(where: { p in
            guard let appt = p.clinicAppointmentDate else { return false }
            return Calendar.current.isDate(appt, equalTo: slot, toGranularity: .minute)
        })
    }

    private func openPatientMedicalRecords(_ patientID: UUID) {
        store.selectedPatientID = patientID

        // ✅ Ask PatientDetailHost to jump to Medical Records tab
        NotificationCenter.default.post(name: .openMedicalRecordsTab, object: nil)
    }

    private func patientDisplayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = p.nameArabic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !en.isEmpty { return en }
        if !ar.isEmpty { return ar }
        return "Unnamed patient"
    }

    // MARK: - Hook for your existing “Clinic/Inpatient” state

    private func needsClinicSwitch() -> Bool {
        // If you have a real property, replace this with it.
        // Example:
        // return patient.isInpatient == true
        return false
    }

    private func setClinicModeIfNeeded(forceClinic: Bool) {
        // Placeholder:
        // If you have a real inpatient/clinic flag on Patient,
        // and forceClinic == true, set it here and save.
        //
        // Example:
        // guard forceClinic else { return }
        // store.patients[idx].isInpatient = false
    }
}

