//
//  SyncManager.swift
//  Second_EMRApp
//
//  Handles offline-first sync with Supabase
//  - Monitors network connectivity
//  - Queues changes when offline
//  - Syncs pending changes when back online
//

import Foundation
import Network
import Combine

@MainActor
public final class SyncManager: ObservableObject {

    public static let shared = SyncManager()

    // MARK: - Published State
    @Published public var isOnline: Bool = true
    @Published public var isSyncing: Bool = false
    @Published public var pendingChangesCount: Int = 0
    @Published public var lastSyncDate: Date?
    @Published public var syncError: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "SyncManager.NetworkMonitor")

    // MARK: - Pending Changes Queue
    private var pendingChanges: [PendingChange] = [] {
        didSet {
            pendingChangesCount = pendingChanges.count
            savePendingChanges()
        }
    }

    private var pendingChangesURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("pending_sync_changes.json")
    }

    private init() {
        loadPendingChanges()
        startNetworkMonitoring()
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOnline == false
                self?.isOnline = path.status == .satisfied

                // Sync when coming back online
                if wasOffline && path.status == .satisfied {
                    await self?.syncPendingChanges()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Queue Operations

    public func queueChange(_ change: PendingChange) {
        pendingChanges.append(change)

        // Try to sync immediately if online
        if isOnline {
            Task {
                await syncPendingChanges()
            }
        }
    }

    public func syncPendingChanges() async {
        print("[SyncManager] syncPendingChanges called. Online: \(isOnline), pending: \(pendingChanges.count), syncing: \(isSyncing)")
        guard isOnline, !pendingChanges.isEmpty else { return }
        guard SupabaseManager.shared.isAuthenticated else {
            print("[SyncManager] Not authenticated, skipping sync")
            syncError = "Not signed in to cloud"
            return
        }

        #if canImport(Supabase)
        isSyncing = true

        var failedChanges: [PendingChange] = []
        var errorMessages: [String] = []

        for change in pendingChanges {
            do {
                print("[SyncManager] Applying change: \(change.entityType) \(change.operation) id=\(change.entityId)")
                try await applyChange(change)
                print("[SyncManager] Change applied successfully")
            } catch {
                let msg = "\(change.entityType)(\(change.operation)): \(error.localizedDescription)"
                print("[SyncManager] FAILED: \(msg)")
                errorMessages.append(msg)
                failedChanges.append(change)
            }
        }

        pendingChanges = failedChanges
        lastSyncDate = Date()
        isSyncing = false

        if !errorMessages.isEmpty {
            syncError = errorMessages.joined(separator: "; ")
        } else {
            syncError = nil
        }
        #endif
    }

    #if canImport(Supabase)
    private func applyChange(_ change: PendingChange) async throws {
        let manager = SupabaseManager.shared
        guard let data = change.payload else {
            print("[SyncManager] No payload for \(change.entityType) \(change.operation)")
            return  // No payload = nothing to push, clear it from queue
        }

        switch change.entityType {
        case .patient:
            if change.operation == .delete {
                try await manager.deletePatient(id: change.entityId)
            } else {
                let patient = try JSONDecoder().decode(Patient.self, from: data)
                try await manager.upsertPatient(patient)
            }

        case .note:
            if change.operation == .delete {
                try await manager.deleteNote(id: change.entityId)
            } else {
                let note = try JSONDecoder().decode(RecordNote.self, from: data)
                try await manager.upsertNote(note)
            }

        case .vital:
            if change.operation == .delete {
                try await manager.deleteVital(id: change.entityId)
            } else {
                let vital = try JSONDecoder().decode(SmartVitalsEntry.self, from: data)
                try await manager.upsertVital(vital)
            }

        case .appointment:
            if change.operation == .delete {
                try await manager.deleteAppointment(id: change.entityId)
            } else {
                let appointment = try JSONDecoder().decode(Appointment.self, from: data)
                try await manager.upsertAppointment(appointment)
            }

        case .physician:
            let physician = try JSONDecoder().decode(Physician.self, from: data)
            try await manager.upsertPhysician(physician)

        case .reference:
            let reference = try JSONDecoder().decode(ReferenceItem.self, from: data)
            try await manager.upsertReference(reference)

        case .attachment:
            // Attachments require special handling for file uploads
            break
        }
    }
    #endif

    // MARK: - Persistence

    private func savePendingChanges() {
        do {
            let data = try JSONEncoder().encode(pendingChanges)
            try data.write(to: pendingChangesURL, options: .atomic)
        } catch {
            print("[SyncManager] Failed to save pending changes: \(error)")
        }
    }

    private func loadPendingChanges() {
        guard FileManager.default.fileExists(atPath: pendingChangesURL.path) else { return }
        do {
            let data = try Data(contentsOf: pendingChangesURL)
            pendingChanges = try JSONDecoder().decode([PendingChange].self, from: data)
        } catch {
            print("[SyncManager] Failed to load pending changes: \(error)")
        }
    }

    // MARK: - Full Sync (Pull from Server)

    func performFullSync(
        emrStore: EMRStore,
        appointmentStore: AppointmentStore,
        physiciansStore: PhysiciansStore,
        referencesStore: ReferencesStore
    ) async {
        guard isOnline else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }

        #if canImport(Supabase)
        isSyncing = true
        var errors: [String] = []

        // Fetch each table independently so one failure doesn't block others
        do {
            let patients = try await SupabaseManager.shared.fetchPatients()
            _ = emrStore.mergePatients(with: patients)
            print("[Sync] Patients: fetched \(patients.count)")
        } catch {
            errors.append("patients: \(error.localizedDescription)")
            print("[Sync] Patients FAILED: \(error)")
        }

        do {
            let notes = try await SupabaseManager.shared.fetchNotes()
            _ = emrStore.mergeNotes(with: notes)
            print("[Sync] Notes: fetched \(notes.count)")
        } catch {
            errors.append("notes: \(error.localizedDescription)")
            print("[Sync] Notes FAILED: \(error)")
        }

        do {
            let vitals = try await SupabaseManager.shared.fetchVitals()
            _ = emrStore.mergeVitals(with: vitals)
            print("[Sync] Vitals: fetched \(vitals.count)")
        } catch {
            errors.append("vitals: \(error.localizedDescription)")
            print("[Sync] Vitals FAILED: \(error)")
        }

        do {
            let appointments = try await SupabaseManager.shared.fetchAppointments()
            _ = appointmentStore.mergeAppointments(with: appointments)
            print("[Sync] Appointments: fetched \(appointments.count)")
        } catch {
            errors.append("appointments: \(error.localizedDescription)")
            print("[Sync] Appointments FAILED: \(error)")
        }

        do {
            let physicians = try await SupabaseManager.shared.fetchPhysicians()
            _ = physiciansStore.mergePhysicians(with: physicians)
            print("[Sync] Physicians: fetched \(physicians.count)")
        } catch {
            errors.append("physicians: \(error.localizedDescription)")
            print("[Sync] Physicians FAILED: \(error)")
        }

        do {
            let references = try await SupabaseManager.shared.fetchReferences()
            _ = referencesStore.mergeItems(with: references)
            print("[Sync] References: fetched \(references.count)")
        } catch {
            errors.append("references: \(error.localizedDescription)")
            print("[Sync] References FAILED: \(error)")
        }

        if errors.isEmpty {
            lastSyncDate = Date()
            syncError = nil
        } else {
            syncError = errors.joined(separator: "; ")
            print("[SyncManager] Sync errors: \(errors)")
        }

        // Push pending changes (must set isSyncing false first)
        isSyncing = false
        await syncPendingChanges()

        #endif
    }
}

// MARK: - Pending Change Model

public struct PendingChange: Codable, Identifiable {
    public let id: UUID
    public let entityType: EntityType
    public let entityId: UUID
    public let operation: Operation
    public let payload: Data?
    public let createdAt: Date

    public enum EntityType: String, Codable {
        case patient, note, vital, appointment, physician, reference, attachment
    }

    public enum Operation: String, Codable {
        case create, update, delete
    }

    public init(entityType: EntityType, entityId: UUID, operation: Operation, payload: Data? = nil) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.payload = payload
        self.createdAt = Date()
    }
}

// MARK: - Convenience Extensions

extension SyncManager {

    func queuePatientChange(_ patient: Patient, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(patient)
        queueChange(PendingChange(entityType: .patient, entityId: patient.id, operation: operation, payload: payload))
    }

    func queueNoteChange(_ note: RecordNote, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(note)
        queueChange(PendingChange(entityType: .note, entityId: note.id, operation: operation, payload: payload))
    }

    func queueVitalChange(_ vital: SmartVitalsEntry, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(vital)
        queueChange(PendingChange(entityType: .vital, entityId: vital.id, operation: operation, payload: payload))
    }

    func queueAppointmentChange(_ appointment: Appointment, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(appointment)
        queueChange(PendingChange(entityType: .appointment, entityId: appointment.id, operation: operation, payload: payload))
    }

    func queuePhysicianChange(_ physician: Physician, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(physician)
        queueChange(PendingChange(entityType: .physician, entityId: physician.id, operation: operation, payload: payload))
    }

    func queueReferenceChange(_ reference: ReferenceItem, operation: PendingChange.Operation) {
        let payload = try? JSONEncoder().encode(reference)
        queueChange(PendingChange(entityType: .reference, entityId: reference.id, operation: operation, payload: payload))
    }
}
