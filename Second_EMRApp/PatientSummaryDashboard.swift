import SwiftUI

struct PatientSummaryDashboard: View {
    let patient: Patient
    @EnvironmentObject private var store: EMRStore
    @StateObject private var appointmentStore = AppointmentStore()
    @State private var showEditDemographics = false
    @State private var workingVitals: SmartVitalsEntry?
    @State private var scheduleDate: Date = Date()

    // MARK: - Computed Properties
    private var notesCount: Int {
        store.notes.filter { $0.patientID == patient.id && !$0.isDeleted }.count
    }

    private var attachmentsCount: Int {
        store.attachments.filter { $0.patientID == patient.id && !$0.isDeleted }.count
    }

    private var recentVitals: [SmartVitalsEntry] {
        store.vitals
            .filter { $0.patientID == patient.id }
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                demographicsCard
                statsCards

                if !recentVitals.isEmpty {
                    recentVitalsCard
                }

                actionButtons

                clinicScheduleSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showEditDemographics) {
            NavigationStack {
                PatientDemographicsView(
                    patient: bindingForPatient(id: patient.id),
                    onSave: {
                        store.savePatient(store.patients.first(where: { $0.id == patient.id }) ?? patient)
                        showEditDemographics = false
                    },
                    onRequestDelete: {
                        showEditDemographics = false
                    }
                )
                .environmentObject(store)
                .navigationTitle("Edit Demographics")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showEditDemographics = false }
                    }
                }
            }
        }
        .sheet(item: $workingVitals) { entry in
            SmartVitalsEntrySheet(
                patient: patient,
                vitals: Binding(
                    get: { workingVitals ?? entry },
                    set: { workingVitals = $0 }
                ),
                onCancel: { workingVitals = nil },
                onInsertIntoNote: { saved in
                    store.addOrUpdateVitals(saved)
                    autoInsertVitalsIntoLatestNote(saved)
                    workingVitals = nil
                },
                onSaveOnly: { saved in
                    store.addOrUpdateVitals(saved)
                    workingVitals = nil
                }
            )
            .environmentObject(store)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 120, height: 120)
                Text(initials)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text(patient.nameEnglish.isEmpty ? "Unnamed Patient" : patient.nameEnglish)
                    .font(.title).bold()

                if !patient.nameArabic.isEmpty {
                    Text(patient.nameArabic).font(.title3).foregroundStyle(.secondary)
                }

                if let age = patient.ageString {
                    Text(age).font(.headline).foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical)
    }

    // MARK: - Demographics Card
    private var demographicsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Patient Information").font(.headline)
                Divider()

                infoRow(label: "MRN", value: patient.mrn.isEmpty ? "—" : patient.mrn, icon: "number")
                infoRow(label: "Gender", value: patient.gender.rawValue, icon: "person")
                infoRow(label: "DOB", value: patient.dob.formatted(date: .abbreviated, time: .omitted), icon: "calendar")

                if !patient.phone.isEmpty {
                    infoRow(label: "Phone", value: patient.phone, icon: "phone")
                }

                if !patient.email.isEmpty {
                    infoRow(label: "Email", value: patient.email, icon: "envelope")
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Quick Stats
    private var statsCards: some View {
        HStack(spacing: 16) {
            statCard(title: "Notes", count: notesCount, icon: "doc.text.fill", color: .blue)
            statCard(title: "Files", count: attachmentsCount, icon: "paperclip", color: .orange)
            statCard(title: "Vitals", count: store.vitals.filter { $0.patientID == patient.id }.count, icon: "waveform.path.ecg", color: .green)
        }
    }

    private func statCard(title: String, count: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(color)
            Text("\(count)").font(.system(size: 32, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recent Vitals Card
    private var recentVitalsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Vitals").font(.headline)
                Divider()

                ForEach(recentVitals, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).bold().foregroundStyle(.blue)

                        Text(entry.formattedBlock(includePercentiles: false, isUnder5: false))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)

                    if entry.id != recentVitals.last?.id { Divider() }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                workingVitals = SmartVitalsEntry(patientID: patient.id)
            } label: {
                Label("Add Vitals", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button { showEditDemographics = true } label: {
                Label("Edit Demographics", systemImage: "pencil")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Clinic Schedule Section
    private var clinicScheduleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Clinic Schedule", systemImage: "calendar")
                        .font(.headline)
                    Spacer()
                    Button("Today") { scheduleDate = Date() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }

                DatePicker("", selection: $scheduleDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()

                Divider()

                // Time slots list
                let slots = generateTimeSlots(for: scheduleDate)
                let dayAppointments = appointmentsForDay(scheduleDate)

                ForEach(slots, id: \.self) { slot in
                    let apt = dayAppointments.first(where: {
                        Calendar.current.isDate($0.startTime, equalTo: slot, toGranularity: .minute)
                    })

                    scheduleSlotRow(slot: slot, appointment: apt)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func scheduleSlotRow(slot: Date, appointment: Appointment?) -> some View {
        if let apt = appointment {
            // Booked slot — show details, no tap action
            HStack(spacing: 12) {
                Text(slot, style: .time)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)

                    if let pid = apt.patientID,
                       let p = store.patients.first(where: { $0.id == pid }) {
                        Text(p.nameEnglish.isEmpty ? "Unnamed" : p.nameEnglish)
                            .font(.caption).bold()
                    } else {
                        Text("Reserved").font(.caption).italic()
                    }

                    if !apt.notes.isEmpty {
                        Text("– \(apt.notes)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text("\(apt.durationMinutes)m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        appointmentStore.delete(id: apt.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            // Empty slot — single tap books this patient immediately
            Button {
                let appointment = Appointment(
                    patientID: patient.id,
                    startTime: slot,
                    durationMinutes: 15
                )
                appointmentStore.add(appointment)
            } label: {
                HStack(spacing: 12) {
                    Text(slot, style: .time)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func generateTimeSlots(for date: Date) -> [Date] {
        var slots: [Date] = []
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: date)

        for hour in 8..<24 {
            for minute in stride(from: 0, to: 60, by: 15) {
                if let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) {
                    slots.append(slot)
                }
            }
        }
        return slots
    }

    private func appointmentsForDay(_ date: Date) -> [Appointment] {
        let calendar = Calendar.current
        return appointmentStore.appointments.filter {
            calendar.isDate($0.startTime, inSameDayAs: date)
        }
    }

    // MARK: - Helpers
    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.blue)
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
        }
    }

    private var initials: String {
        let name = patient.nameEnglish.isEmpty ? "?" : patient.nameEnglish
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    private func autoInsertVitalsIntoLatestNote(_ vitals: SmartVitalsEntry) {
        guard let idx = store.notes.firstIndex(where: {
            $0.patientID == patient.id && !$0.isDeleted && !$0.isFinalized
        }) else { return }

        let vitalsText = "\n" + vitals.formattedBlockCompact(patient: patient, useAI: false) + "\n"
        var lines = store.notes[idx].body.components(separatedBy: "\n")

        let keywords = ["physical examination", "objective", "exam:", "examination:", "pe:", "o:"]
        var insertAt: Int?
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if keywords.contains(where: { lower.contains($0) || lower.hasPrefix($0) }) {
                insertAt = i + 1
                break
            }
        }

        if let at = insertAt, at <= lines.count {
            lines.insert(vitalsText, at: at)
        } else {
            lines.append(vitalsText)
        }

        store.notes[idx].body = lines.joined(separator: "\n")
        store.saveNote(store.notes[idx])
    }

    private func bindingForPatient(id: UUID) -> Binding<Patient> {
        Binding(
            get: { store.patients.first(where: { $0.id == id }) ?? Patient() },
            set: { newValue in
                if let index = store.patients.firstIndex(where: { $0.id == id }) {
                    store.patients[index] = newValue
                }
            }
        )
    }
}
