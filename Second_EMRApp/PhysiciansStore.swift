//
//  PhysiciansStore.swift
//  Second_EMRApp
//

import Foundation
import Combine

public struct Physician: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var name: String
    public var specialty: String
    public var clinic: String
    public var phone: String
    public var email: String

    // Soft delete (per your rule)
    public var isDeleted: Bool = false

    public init(
        id: UUID = UUID(),
        name: String,
        specialty: String = "",
        clinic: String = "",
        phone: String = "",
        email: String = "",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.specialty = specialty
        self.clinic = clinic
        self.phone = phone
        self.email = email
        self.isDeleted = isDeleted
    }

    public var displayName: String {
        specialty.isEmpty ? name : "\(name) • \(specialty)"
    }
}

@MainActor
public final class PhysiciansStore: ObservableObject {

    @Published public var physicians: [Physician] = []
    @Published public var selectedPhysicianID: UUID? = nil

    private var fileURL: URL {
        iCloudSyncManager.shared.url(for: "physicians.json")
    }

    public init() {
        load()

        if physicians.isEmpty {
            let def = Physician(
                name: "Attending Neurosurgeon",
                specialty: "Neurosurgery",
                clinic: "Main Hospital"
            )
            physicians = [def]
            selectedPhysicianID = def.id
            save()
        } else if selectedPhysicianID == nil {
            selectedPhysicianID = physicians.first(where: { !$0.isDeleted })?.id
        }

        iCloudSyncManager.shared.registerForChanges(filename: "physicians.json") { [weak self] in
            Task { @MainActor in self?.load() }
        }
    }

    // MARK: - Derived
    public var activePhysicians: [Physician] {
        physicians.filter { !$0.isDeleted }
    }

    public var selectedPhysician: Physician? {
        guard let id = selectedPhysicianID else { return nil }
        return physicians.first(where: { $0.id == id && !$0.isDeleted })
    }

    // MARK: - CRUD
    public func add(_ physician: Physician) {
        physicians.insert(physician, at: 0)
        selectedPhysicianID = physician.id
        save()
    }

    public func update(_ physician: Physician) {
        guard let idx = physicians.firstIndex(where: { $0.id == physician.id }) else { return }
        physicians[idx] = physician
        save()
    }

    // ✅ Soft delete (your rule)
    public func softDelete(_ id: UUID) {
        guard let idx = physicians.firstIndex(where: { $0.id == id }) else { return }
        physicians[idx].isDeleted = true
        if selectedPhysicianID == id {
            selectedPhysicianID = activePhysicians.first?.id
        }
        save()
    }

    public func restore(_ id: UUID) {
        guard let idx = physicians.firstIndex(where: { $0.id == id }) else { return }
        physicians[idx].isDeleted = false
        if selectedPhysicianID == nil {
            selectedPhysicianID = id
        }
        save()
    }

    // MARK: - Backup & Merge

    public func replaceAll(with newPhysicians: [Physician]) {
        physicians = newPhysicians
        if selectedPhysicianID == nil || !physicians.contains(where: { $0.id == selectedPhysicianID }) {
            selectedPhysicianID = physicians.first(where: { !$0.isDeleted })?.id
        }
        save()
    }

    /// Merge incoming physicians by UUID (add if new).
    public func mergePhysicians(with incoming: [Physician]) -> Int {
        let existingIDs = Set(physicians.map { $0.id })
        let newItems = incoming.filter { !existingIDs.contains($0.id) }

        if !newItems.isEmpty {
            physicians.append(contentsOf: newItems)
            save()
        }
        return newItems.count
    }

    // MARK: - Persistence (file-based for iCloud sync)

    private struct PhysiciansPayload: Codable {
        var physicians: [Physician]
        var selectedPhysicianID: UUID?
    }

    public func save() {
        do {
            let payload = PhysiciansPayload(physicians: physicians, selectedPhysicianID: selectedPhysicianID)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[PhysiciansStore] save error: \(error)")
        }
    }

    private func load() {
        // Try file-based storage first
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let payload = try JSONDecoder().decode(PhysiciansPayload.self, from: data)
                physicians = payload.physicians
                selectedPhysicianID = payload.selectedPhysicianID
                return
            } catch {
                print("[PhysiciansStore] file load error: \(error)")
            }
        }

        // Migrate from UserDefaults (one-time)
        if let data = UserDefaults.standard.data(forKey: "physicians_data_v2"),
           let decoded = try? JSONDecoder().decode([Physician].self, from: data) {
            physicians = decoded
            if let s = UserDefaults.standard.string(forKey: "physician_selected_id_v2"),
               let id = UUID(uuidString: s) {
                selectedPhysicianID = id
            }
            save()
            UserDefaults.standard.removeObject(forKey: "physicians_data_v2")
            UserDefaults.standard.removeObject(forKey: "physician_selected_id_v2")
        }
    }
}

