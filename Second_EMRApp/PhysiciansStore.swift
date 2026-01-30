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

    private let physiciansKey = "physicians_data_v2"
    private let selectedIDKey = "physician_selected_id_v2"

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

    // MARK: - Persistence
    public func save() {
        if let data = try? JSONEncoder().encode(physicians) {
            UserDefaults.standard.set(data, forKey: physiciansKey)
        }
        if let id = selectedPhysicianID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedIDKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: physiciansKey),
           let decoded = try? JSONDecoder().decode([Physician].self, from: data) {
            physicians = decoded
        }
        if let s = UserDefaults.standard.string(forKey: selectedIDKey),
           let id = UUID(uuidString: s) {
            selectedPhysicianID = id
        }
    }
}

