import Foundation
import Combine

// MARK: - Physician Model

public struct Physician: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var specialty: String = ""
    public var clinic: String = ""
    public var licenseNumber: String = ""
    public var contactPhone: String = ""
    public var contactEmail: String = ""

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init() { }
}

// MARK: - Physicians Store

@MainActor
public final class PhysiciansStore: ObservableObject {

    @Published public var physicians: [Physician] = []
    @Published public var selectedPhysicianID: UUID? = nil

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var physiciansURL: URL {
        documentsURL.appendingPathComponent("physicians.json")
    }

    public init() {
        load()

        // ✅ If we have physicians but nothing selected, select the first one
        // so the physician name shows in the card immediately.
        if selectedPhysicianID == nil {
            selectedPhysicianID = physicians.first?.id
        }
    }

    public var selectedPhysician: Physician? {
        guard let id = selectedPhysicianID else { return nil }
        return physicians.first(where: { $0.id == id })
    }

    public var selectedPhysicianName: String? {
        selectedPhysician?.name
    }

    public func save() {
        do {
            let data = try JSONEncoder().encode(physicians)
            try data.write(to: physiciansURL, options: [.atomic])

            if let id = selectedPhysicianID {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedPhysicianID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedPhysicianID")
            }
        } catch {
            print("Failed to save physicians: \(error)")
        }
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: physiciansURL.path) {
                let data = try Data(contentsOf: physiciansURL)
                physicians = try JSONDecoder().decode([Physician].self, from: data)
            } else {
                physicians = []
            }

            // Load selected ID (even if file missing; we validate below)
            if let idString = UserDefaults.standard.string(forKey: "selectedPhysicianID"),
               let id = UUID(uuidString: idString) {
                selectedPhysicianID = id
            }

            // ✅ Validate selection still exists; otherwise fall back to first physician.
            if let sel = selectedPhysicianID,
               physicians.contains(where: { $0.id == sel }) == false {
                selectedPhysicianID = physicians.first?.id
            }
        } catch {
            print("Failed to load physicians: \(error)")
            physicians = []
        }
    }

    public func addPhysician() -> Physician {
        let p = Physician()
        physicians.append(p)
        save()
        return p
    }

    public func updatePhysician(_ physician: Physician) {
        if let idx = physicians.firstIndex(where: { $0.id == physician.id }) {
            physicians[idx] = physician
            save()
        }
    }

    public func deletePhysician(id: UUID) {
        if let idx = physicians.firstIndex(where: { $0.id == id }) {
            physicians.remove(at: idx)
            if selectedPhysicianID == id {
                selectedPhysicianID = nil
            }
            save()
        }
    }
}
