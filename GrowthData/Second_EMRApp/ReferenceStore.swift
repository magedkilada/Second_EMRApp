import Foundation
import Combine

// MARK: - Model

struct ReferenceItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var category: String
    var body: String              // markdown or plain text
    var isFavorite: Bool = false
    var updatedAt: Date = Date()
}

// MARK: - Store

@MainActor
final class ReferencesStore: ObservableObject {

    @Published var items: [ReferenceItem] = [
        ReferenceItem(
            title: "Glasgow Coma Scale (GCS)",
            category: "Scales",
            body: """
GCS = Eye (E) + Verbal (V) + Motor (M)

E: 4 spontaneous / 3 to speech / 2 to pain / 1 none
V: 5 oriented / 4 confused / 3 inappropriate / 2 incomprehensible / 1 none
M: 6 obeys / 5 localizes / 4 withdraws / 3 flexion / 2 extension / 1 none
"""
        ),
        ReferenceItem(
            title: "Hunt & Hess Grade",
            category: "Scales",
            body: """
Grade 1–5 (brief description here)
"""
        ),
        ReferenceItem(
            title: "Fisher Grade",
            category: "Scales",
            body: """
Grade 1–4 (brief description here)
"""
        ),
        ReferenceItem(
            title: "AO Spine Fracture Classification",
            category: "Protocols",
            body: """
AO A0–A4, B, C (brief outline here)
"""
        )
    ]

    func item(with id: UUID?) -> ReferenceItem? {
        guard let id else { return nil }
        return items.first(where: { $0.id == id })
    }

    func addBlank() -> ReferenceItem {
        let new = ReferenceItem(title: "New Reference", category: "Unsorted", body: "")
        items.insert(new, at: 0)
        return new
    }

    func delete(_ item: ReferenceItem) {
        items.removeAll { $0.id == item.id }
    }

    func toggleFavorite(_ item: ReferenceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        items[idx].updatedAt = Date()
    }

    func update(_ item: ReferenceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        items[idx].updatedAt = Date()
    }
}
