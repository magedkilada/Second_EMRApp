import Foundation
import SwiftUI
import Combine

// MARK: - Reference Item Model

public struct ReferenceItem: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var title: String
    public var category: String
    public var body: String
    public var isFavorite: Bool = false
    public var createdAt: Date = Date()
    
    public init(title: String = "", category: String = "", body: String = "") {
        self.title = title
        self.category = category
        self.body = body
    }
}

// MARK: - References Store

@MainActor
public final class ReferencesStore: ObservableObject {
    
    @Published public var items: [ReferenceItem] = []
    
    private let storageKey = "references_v1"
    
    public init() {
        load()
        
        // Add default references if empty
        if items.isEmpty {
            addDefaultReferences()
        }
    }
    
    // MARK: - CRUD
    
    public func addBlank() -> ReferenceItem {
        let item = ReferenceItem(title: "New Reference", category: "General", body: "")
        items.insert(item, at: 0)
        save()
        return item
    }
    
    public func update(_ item: ReferenceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }
    
    public func delete(_ item: ReferenceItem) {
        items.removeAll(where: { $0.id == item.id })
        save()
    }
    
    public func toggleFavorite(_ item: ReferenceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        save()
    }
    
    // MARK: - Storage
    
    public func save() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("❌ Failed to save references:", error)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ReferenceItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }
    
    // MARK: - Default Content
    
    private func addDefaultReferences() {
        let gcs = ReferenceItem(
            title: "Glasgow Coma Scale (GCS)",
            category: "Neurosurgery",
            body: """
GLASGOW COMA SCALE (GCS)

Eye Opening (E):
4 - Spontaneous
3 - To speech
2 - To pain
1 - None

Verbal Response (V):
5 - Oriented
4 - Confused
3 - Inappropriate words
2 - Incomprehensible sounds
1 - None

Motor Response (M):
6 - Obeys commands
5 - Localizes pain
4 - Withdraws from pain
3 - Flexion to pain (decorticate)
2 - Extension to pain (decerebrate)
1 - None

Total Score: E + V + M (3-15)
• 13-15: Mild injury
• 9-12: Moderate injury
• 3-8: Severe injury
"""
        )
        
        let huntHess = ReferenceItem(
            title: "Hunt & Hess Grade (SAH)",
            category: "Neurosurgery",
            body: """
HUNT & HESS GRADING (Subarachnoid Hemorrhage)

Grade 1: Asymptomatic or mild headache, slight nuchal rigidity

Grade 2: Moderate to severe headache, nuchal rigidity, cranial nerve palsy

Grade 3: Drowsiness, confusion, mild focal deficit

Grade 4: Stupor, moderate to severe hemiparesis, early decerebrate rigidity

Grade 5: Deep coma, decerebrate rigidity, moribund appearance
"""
        )
        
        let fisher = ReferenceItem(
            title: "Fisher Grade (SAH)",
            category: "Neurosurgery",
            body: """
FISHER GRADE (CT appearance of SAH)

Grade 1: No blood detected

Grade 2: Diffuse thin SAH (<1mm)

Grade 3: Localized clot and/or thick SAH (>1mm)

Grade 4: Diffuse or no SAH with intraventricular or intraparenchymal blood

Modified Fisher Scale:
0 - No SAH or IVH
1 - Thin SAH, no IVH
2 - Thin SAH with IVH
3 - Thick SAH, no IVH
4 - Thick SAH with IVH
"""
        )
        
        items = [gcs, huntHess, fisher]
        save()
    }
}

