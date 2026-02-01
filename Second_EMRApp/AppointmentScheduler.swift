//
//  AppointmentScheduler.swift - 15-MINUTE INTERVALS
//  Second_EMRApp
//

import SwiftUI
import Combine

struct Appointment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var patientID: UUID?
    var startTime: Date
    var durationMinutes: Int
    var notes: String
    var createdAt: Date = Date()
    
    init(patientID: UUID? = nil, startTime: Date, durationMinutes: Int = 15, notes: String = "") {
        self.patientID = patientID
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.notes = notes
    }
}

@MainActor
final class AppointmentStore: ObservableObject {
    @Published var appointments: [Appointment] = []
    
    private let appointmentsKey = "appointments_data" // Standardized key
    
    init() { load() }
    
    func add(_ appointment: Appointment) {
        appointments.append(appointment)
        save()
    }
    
    func delete(id: UUID) {
        appointments.removeAll(where: { $0.id == id })
        save()
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(appointments) {
            UserDefaults.standard.set(data, forKey: appointmentsKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: appointmentsKey),
           let decoded = try? JSONDecoder().decode([Appointment].self, from: data) {
            appointments = decoded
        }
    }
}

struct ScheduleView: View {
    @EnvironmentObject private var appointmentStore: AppointmentStore
    @EnvironmentObject private var emrStore: EMRStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedDate: Date = Date()
    @State private var showAddAppointment = false
    @State private var selectedTimeSlot: Date?
    
    private func generateTimeSlots() -> [Date] {
        var slots: [Date] = []
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: selectedDate)
        
        // Clinic hours: 08:00 to midnight
        for hour in 8..<24 {
            for minute in stride(from: 0, to: 60, by: 15) {
                if let slot = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDate) {
                    slots.append(slot)
                }
            }
        }
        return slots
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                
                Divider()
                
                List {
                    ForEach(generateTimeSlots(), id: \.self) { slot in
                        timeSlotRow(for: slot)
                            .swipeActions(edge: .trailing) {
                                if let apt = appointmentForSlot(slot) {
                                    Button(role: .destructive) {
                                        appointmentStore.delete(id: apt.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Clinic Schedule")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Today") { selectedDate = Date() }
                }
            }
            .sheet(isPresented: $showAddAppointment) {
                if let timeSlot = selectedTimeSlot {
                    AddAppointmentView(
                        timeSlot: timeSlot,
                        onSave: { appointment in
                            appointmentStore.add(appointment)
                            showAddAppointment = false
                        }
                    )
                    .environmentObject(emrStore)
                }
            }
        }
    }
    
    private func timeSlotRow(for slot: Date) -> some View {
        let calendar = Calendar.current
        let appointment = appointmentStore.appointments.first(where: {
            calendar.isDate($0.startTime, equalTo: slot, toGranularity: .minute)
        })
        
        return Button {
            selectedTimeSlot = slot
            showAddAppointment = true
        } label: {
            HStack(spacing: 15) {
                Text(slot, style: .time)
                    .font(.system(.subheadline, design: .monospaced))
                    .frame(width: 70, alignment: .leading)
                    .foregroundStyle(.secondary)
                
                if let apt = appointment {
                    VStack(alignment: .leading, spacing: 2) {
                        if let patientID = apt.patientID,
                           let patient = emrStore.patients.first(where: { $0.id == patientID }) {
                            Text(patientDisplayName(patient))
                                .font(.subheadline).bold()
                        } else {
                            Text("Reserved Slot").font(.subheadline).italic()
                        }
                        
                        if !apt.notes.isEmpty {
                            Text(apt.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text("Available Slot")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appointmentForSlot(_ slot: Date) -> Appointment? {
        let calendar = Calendar.current
        return appointmentStore.appointments.first(where: {
            calendar.isDate($0.startTime, equalTo: slot, toGranularity: .minute)
        })
    }

    private func patientDisplayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        return en.isEmpty ? "New Patient" : en
    }
}

struct AddAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var emrStore: EMRStore
    
    let timeSlot: Date
    let onSave: (Appointment) -> Void
    var initialPatientID: UUID? = nil

    @State private var selectedPatientID: UUID?
    @State private var duration: Int = 15
    @State private var notes: String = ""
    
    private let durations = [15, 30, 45, 60, 90, 120]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Start Time")
                        Spacer()
                        Text(timeSlot, style: .time).foregroundStyle(.blue).bold()
                    }
                    Picker("Duration", selection: $duration) {
                        ForEach(durations, id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                } header: { Text("Time Slot") }
                
                Section {
                    Picker("Select Patient", selection: $selectedPatientID) {
                        Text("Unassigned / Generic").tag(nil as UUID?)
                        Divider()
                        ForEach(emrStore.patients.filter { !$0.isDeleted }) { patient in
                            Text(patientDisplayName(patient)).tag(patient.id as UUID?)
                        }
                    }
                } header: { Text("Patient Information") }
                
                Section {
                    TextField("Reason for visit, surgery follow-up, etc.", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                } header: { Text("Clinical Notes") }
            }
            .navigationTitle("Schedule Appointment")
            .onAppear {
                if selectedPatientID == nil, let initial = initialPatientID {
                    selectedPatientID = initial
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let appointment = Appointment(
                            patientID: selectedPatientID,
                            startTime: timeSlot,
                            durationMinutes: duration,
                            notes: notes
                        )
                        onSave(appointment)
                    }
                }
            }
        }
    }
    
    private func patientDisplayName(_ p: Patient) -> String {
        let en = p.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        return en.isEmpty ? "Unnamed" : en
    }
}

