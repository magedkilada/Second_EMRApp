//
//  ReferencesStore.swift
//  Second_EMRApp
//

import Foundation
import Combine

public struct ReferenceItem: Identifiable, Hashable, Codable {
    public enum Category: String, CaseIterable, Codable, Hashable {
        case scales = "Clinical Scales"
        case guidelines = "Guidelines"
        case procedures = "Procedures"
        case medications = "Medications"
        case misc = "Misc"
    }

    public var id: UUID = UUID()
    public var title: String
    public var category: Category
    public var body: String
    public var isFavorite: Bool = false

    public init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        body: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.isFavorite = isFavorite
    }
}

@MainActor
public final class ReferencesStore: ObservableObject {

    @Published public var items: [ReferenceItem] = []
    @Published public var selectedCategory: ReferenceItem.Category? = nil

    private static let fileName = "references.json"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    public init() {
        loadFromDisk()
        if items.isEmpty {
            loadDefaults()
            saveToDisk()
        }
    }

    public var filteredItems: [ReferenceItem] {
        guard let cat = selectedCategory else { return items }
        return items.filter { $0.category == cat }
    }

    @discardableResult
    public func addBlank() -> ReferenceItem {
        let item = ReferenceItem(title: "New Reference", category: .misc, body: "")
        items.insert(item, at: 0)
        saveToDisk()
        return item
    }

    public func update(_ item: ReferenceItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        saveToDisk()
    }

    public func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            print("[ReferencesStore] save error: \(error)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: Self.fileURL)
            items = try JSONDecoder().decode([ReferenceItem].self, from: data)
        } catch {
            print("[ReferencesStore] load error: \(error)")
        }
    }

    // MARK: - Defaults
    private func loadDefaults() {
        items = [
            ReferenceItem(
                title: "Glasgow Coma Scale (GCS)",
                category: .scales,
                body:
"""
GCS (3–15)

Eye Opening (E)
4: Spontaneous
3: To voice
2: To pain
1: None

Verbal (V)
5: Oriented
4: Confused
3: Inappropriate words
2: Incomprehensible sounds
1: None

Motor (M)
6: Obeys commands
5: Localizes pain
4: Withdraws
3: Flexion
2: Extension
1: None
"""
            )
        ]
    }
}

