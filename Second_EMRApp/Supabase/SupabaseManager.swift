//
//  SupabaseManager.swift
//  Second_EMRApp
//
//  Singleton for all Supabase operations: Auth, CRUD, Real-time
//
//  SETUP: Add Supabase Swift SDK via Swift Package Manager
//  https://github.com/supabase/supabase-swift (version 2.0.0+)
//

import Foundation
import Combine

#if canImport(Supabase)
import Supabase

@MainActor
public final class SupabaseManager: ObservableObject {

    public static let shared = SupabaseManager()

    // MARK: - Published State
    @Published public var currentUser: User?
    @Published public var currentProfile: UserProfile?
    @Published public var isAuthenticated: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var authError: String?

    // MARK: - Offline Queue
    @Published public var pendingChangesCount: Int = 0

    private var client: SupabaseClient { SupabaseConfig.client }
    private var realtimeChannels: [RealtimeChannelV2] = []

    private init() {
        Task {
            await checkSession()
        }
    }

    // MARK: - Auth

    public func checkSession() async {
        do {
            let session = try await client.auth.session
            currentUser = session.user
            isAuthenticated = true
            await loadProfile()
        } catch {
            currentUser = nil
            currentProfile = nil
            isAuthenticated = false
        }
    }

    public func signUp(email: String, password: String, fullName: String, role: UserRole) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let response = try await client.auth.signUp(
                email: email,
                password: password,
                data: [
                    "full_name": .string(fullName),
                    "role": .string(role.rawValue)
                ]
            )
            currentUser = response.user
            isAuthenticated = true
            await loadProfile()
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    public func signIn(email: String, password: String) async throws {
        isLoading = true
        authError = nil
        defer { isLoading = false }

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            currentUser = session.user
            isAuthenticated = true
            await loadProfile()
        } catch {
            authError = error.localizedDescription
            throw error
        }
    }

    public func signOut() async throws {
        try await client.auth.signOut()
        currentUser = nil
        currentProfile = nil
        isAuthenticated = false
        unsubscribeAll()
    }

    private func loadProfile() async {
        guard let userId = currentUser?.id else { return }
        do {
            let profile: UserProfile = try await client.database
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            currentProfile = profile
        } catch {
            print("[SupabaseManager] Failed to load profile: \(error)")
        }
    }

    // MARK: - Role Check

    public var currentRole: UserRole {
        currentProfile?.role ?? .secretary
    }

    // MARK: - CRUD Operations

    // Patients
    func fetchPatients() async throws -> [Patient] {
        try await client.database
            .from("patients")
            .select()
            .eq("is_deleted", value: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func upsertPatient(_ patient: Patient) async throws {
        try await client.database
            .from("patients")
            .upsert(patient)
            .execute()
    }

    func deletePatient(id: UUID) async throws {
        try await client.database
            .from("patients")
            .update(["is_deleted": true])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // Notes
    func fetchNotes(patientId: UUID? = nil) async throws -> [RecordNote] {
        var query = client.database
            .from("notes")
            .select()
            .eq("is_deleted", value: false)

        if let patientId = patientId {
            query = query.eq("patient_id", value: patientId.uuidString)
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func upsertNote(_ note: RecordNote) async throws {
        guard currentRole.canManageNotes else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("notes")
            .upsert(note)
            .execute()
    }

    func deleteNote(id: UUID) async throws {
        guard currentRole.canManageNotes else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("notes")
            .update(["is_deleted": true])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // Vitals
    func fetchVitals(patientId: UUID? = nil) async throws -> [SmartVitalsEntry] {
        var query = client.database
            .from("vitals")
            .select()

        if let patientId = patientId {
            query = query.eq("patient_id", value: patientId.uuidString)
        }

        return try await query
            .order("recorded_at", ascending: false)
            .execute()
            .value
    }

    func upsertVital(_ vital: SmartVitalsEntry) async throws {
        guard currentRole.canManageVitals else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("vitals")
            .upsert(vital)
            .execute()
    }

    func deleteVital(id: UUID) async throws {
        guard currentRole.canManageVitals else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("vitals")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // Appointments
    func fetchAppointments() async throws -> [Appointment] {
        try await client.database
            .from("appointments")
            .select()
            .order("start_time", ascending: true)
            .execute()
            .value
    }

    func upsertAppointment(_ appointment: Appointment) async throws {
        guard currentRole.canManageAppointments else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("appointments")
            .upsert(appointment)
            .execute()
    }

    func deleteAppointment(id: UUID) async throws {
        guard currentRole.canManageAppointments else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("appointments")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // Physicians
    func fetchPhysicians() async throws -> [Physician] {
        try await client.database
            .from("physicians")
            .select()
            .eq("is_deleted", value: false)
            .execute()
            .value
    }

    func upsertPhysician(_ physician: Physician) async throws {
        guard currentRole.canManagePhysicians else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("physicians")
            .upsert(physician)
            .execute()
    }

    // References
    func fetchReferences() async throws -> [ReferenceItem] {
        try await client.database
            .from("medical_references")
            .select()
            .order("title", ascending: true)
            .execute()
            .value
    }

    func upsertReference(_ reference: ReferenceItem) async throws {
        guard currentRole.canManageReferences else {
            throw SupabaseError.insufficientPermissions
        }
        try await client.database
            .from("medical_references")
            .upsert(reference)
            .execute()
    }

    // MARK: - File Storage

    public func uploadAttachment(data: Data, path: String, contentType: String) async throws -> String {
        try await client.storage
            .from(SupabaseConfig.attachmentsBucket)
            .upload(path, data: data, options: .init(contentType: contentType))
        return path
    }

    public func downloadAttachment(path: String) async throws -> Data {
        try await client.storage
            .from(SupabaseConfig.attachmentsBucket)
            .download(path: path)
    }

    public func deleteAttachment(path: String) async throws {
        try await client.storage
            .from(SupabaseConfig.attachmentsBucket)
            .remove(paths: [path])
    }

    public func getAttachmentURL(path: String) -> URL? {
        try? client.storage
            .from(SupabaseConfig.attachmentsBucket)
            .getPublicURL(path: path)
    }

    // MARK: - Real-time Subscriptions

    func subscribeToPatients(onChange: @escaping ([Patient]) -> Void) async {
        let channel = client.channel("patients-changes")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "patients"
        )

        await channel.subscribe()
        realtimeChannels.append(channel)

        Task {
            for await _ in changes {
                if let patients = try? await fetchPatients() {
                    await MainActor.run {
                        onChange(patients)
                    }
                }
            }
        }
    }

    func subscribeToNotes(onChange: @escaping ([RecordNote]) -> Void) async {
        let channel = client.channel("notes-changes")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "notes"
        )

        await channel.subscribe()
        realtimeChannels.append(channel)

        Task {
            for await _ in changes {
                if let notes = try? await fetchNotes() {
                    await MainActor.run {
                        onChange(notes)
                    }
                }
            }
        }
    }

    func unsubscribeAll() {
        for channel in realtimeChannels {
            Task {
                await channel.unsubscribe()
            }
        }
        realtimeChannels.removeAll()
    }
}

// MARK: - Errors

public enum SupabaseError: LocalizedError {
    case insufficientPermissions
    case notAuthenticated
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "You don't have permission to perform this action."
        case .notAuthenticated:
            return "Please sign in to continue."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

#else

// MARK: - Stub Implementation (when Supabase SDK not installed)

@MainActor
public final class SupabaseManager: ObservableObject {
    public static let shared = SupabaseManager()

    @Published public var currentProfile: UserProfile?
    @Published public var isAuthenticated: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var authError: String?
    @Published public var pendingChangesCount: Int = 0

    private init() {}

    public var currentRole: UserRole { currentProfile?.role ?? .physician }

    public func checkSession() async {}
    public func signUp(email: String, password: String, fullName: String, role: UserRole) async throws {
        throw SupabaseError.notConfigured
    }
    public func signIn(email: String, password: String) async throws {
        throw SupabaseError.notConfigured
    }
    public func signOut() async throws {}

    // Stub CRUD methods
    func fetchPatients() async throws -> [Patient] { [] }
    func upsertPatient(_ patient: Patient) async throws {}
    func deletePatient(id: UUID) async throws {}
    func fetchNotes(patientId: UUID? = nil) async throws -> [RecordNote] { [] }
    func upsertNote(_ note: RecordNote) async throws {}
    func deleteNote(id: UUID) async throws {}
    func fetchVitals(patientId: UUID? = nil) async throws -> [SmartVitalsEntry] { [] }
    func upsertVital(_ vital: SmartVitalsEntry) async throws {}
    func deleteVital(id: UUID) async throws {}
    func fetchAppointments() async throws -> [Appointment] { [] }
    func upsertAppointment(_ appointment: Appointment) async throws {}
    func deleteAppointment(id: UUID) async throws {}
    func fetchPhysicians() async throws -> [Physician] { [] }
    func upsertPhysician(_ physician: Physician) async throws {}
    func fetchReferences() async throws -> [ReferenceItem] { [] }
    func upsertReference(_ reference: ReferenceItem) async throws {}

    func subscribeToPatients(onChange: @escaping ([Patient]) -> Void) async {}
    func subscribeToNotes(onChange: @escaping ([RecordNote]) -> Void) async {}
    func unsubscribeAll() {}
}

public enum SupabaseError: LocalizedError {
    case insufficientPermissions
    case notAuthenticated
    case notConfigured
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .insufficientPermissions:
            return "You don't have permission to perform this action."
        case .notAuthenticated:
            return "Please sign in to continue."
        case .notConfigured:
            return "Supabase SDK not installed. Add via Swift Package Manager."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

#endif
