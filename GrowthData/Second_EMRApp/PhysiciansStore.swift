import Foundation
import SwiftUI
import Combine   // ✅ REQUIRED

// MARK: - Model

struct Physician: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var specialty: String
    var clinic: String

    // ✅ ADD THIS
    var fullName: String {
        name
    }
}

// MARK: - Store

@MainActor
final class PhysiciansStore: ObservableObject {

    @Published var physicians: [Physician] = []
    @Published var selectedPhysicianID: UUID? = nil
    // Put this inside PhysiciansStore class (below @Published vars)
    public var selectedPhysicianName: String? {
        physicians.first(where: { $0.id == selectedPhysicianID })?.name
    }
    public var selectedPhysicianDisplay: String {
        guard let p = physicians.first(where: { $0.id == selectedPhysicianID }) else { return "—" }
        return p.specialty.isEmpty ? p.name : "\(p.name) • \(p.specialty)"
    }
    
    

    private let physiciansKey = "physicians.json"
    private let selectedIDKey = "physician.selectedID"

    init() {
        load()
        if physicians.isEmpty {
            // Default physician (optional)
            let p = Physician(name: "Attending Physician", specialty: "Neurosurgery", clinic: "")
            physicians = [p]
            selectedPhysicianID = p.id
            save()
        } else if selectedPhysicianID == nil {
            selectedPhysicianID = physicians.first?.id
        }
    }

    var selectedPhysician: Physician? {
        guard let id = selectedPhysicianID else { return nil }
        return physicians.first(where: { $0.id == id })
    }

    func add(_ p: Physician) {
        physicians.insert(p, at: 0)
        selectedPhysicianID = p.id
        save()
    }

    func delete(id: UUID) {
        physicians.removeAll(where: { $0.id == id })
        if selectedPhysicianID == id {
            selectedPhysicianID = physicians.first?.id
        }
        save()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(physicians)
            UserDefaults.standard.set(data, forKey: physiciansKey)

            if let id = selectedPhysicianID {
                UserDefaults.standard.set(id.uuidString, forKey: selectedIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedIDKey)
            }
        } catch {
            print("PhysiciansStore save failed:", error)
        }
    }
    
    func update(_ p: Physician) {
        if let idx = physicians.firstIndex(where: { $0.id == p.id }) {
            physicians[idx] = p
            save()
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: physiciansKey),
           let decoded = try? JSONDecoder().decode([Physician].self, from: data) {
            physicians = decoded
        } else {
            physicians = []
        }

        if let s = UserDefaults.standard.string(forKey: selectedIDKey),
           let id = UUID(uuidString: s) {
            selectedPhysicianID = id
        } else {
            selectedPhysicianID = nil
        }
    }
}
