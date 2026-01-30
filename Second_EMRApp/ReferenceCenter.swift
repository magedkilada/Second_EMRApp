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
    public var filePath: String? = nil

    public init(
        id: UUID = UUID(),
        title: String,
        category: Category,
        body: String,
        isFavorite: Bool = false,
        filePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.body = body
        self.isFavorite = isFavorite
        self.filePath = filePath
    }

    /// Resolved file URL, if file exists on disk.
    /// `filePath` stores a relative path (e.g. "ReferenceFiles/file.pdf"),
    /// resolved against the shared References base directory (iCloud or local).
    public var fileURL: URL? {
        guard let path = filePath, !path.isEmpty else { return nil }

        let base = ReferencesStore.baseDirectory

        // Support both relative and legacy absolute paths
        let url: URL
        if path.hasPrefix("/") {
            // Legacy absolute path — extract the relative portion
            if let range = path.range(of: "Documents/") {
                let relative = String(path[range.upperBound...])
                url = base.appendingPathComponent(relative)
            } else {
                url = URL(fileURLWithPath: path)
            }
        } else {
            url = base.appendingPathComponent(path)
        }

        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
public final class ReferencesStore: ObservableObject {

    @Published public var items: [ReferenceItem] = []
    @Published public var selectedCategory: ReferenceItem.Category? = nil

    private static let fileName = "references.json"

    // MARK: - iCloud-aware base directory

    /// Shared base directory for references data + files.
    /// Uses iCloud Documents if available, otherwise local Documents.
    public static var baseDirectory: URL {
        if let icloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") {
            try? FileManager.default.createDirectory(at: icloud, withIntermediateDirectories: true)
            return icloud
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Directory for imported reference files (PDFs, images, etc.)
    public static var referenceFilesDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("ReferenceFiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for imported reference photos
    public static var referencePhotosDirectory: URL {
        let dir = baseDirectory.appendingPathComponent("ReferencePhotos")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL {
        baseDirectory.appendingPathComponent(fileName)
    }

    public static var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public init() {
        migrateLocalToICloudIfNeeded()
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

    /// Insert a new item and persist immediately.
    public func add(_ item: ReferenceItem) {
        items.insert(item, at: 0)
        saveToDisk()
    }

    public func update(_ item: ReferenceItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.insert(item, at: 0)
        }
        saveToDisk()
    }

    public func delete(_ id: UUID) {
        // Also remove the associated file if present
        if let item = items.first(where: { $0.id == id }),
           let fileURL = item.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
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

    // MARK: - Local → iCloud Migration

    /// One-time migration: if iCloud is available and local data exists
    /// but iCloud data doesn't, copy everything to iCloud.
    private func migrateLocalToICloudIfNeeded() {
        guard Self.isICloudAvailable else { return }

        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localJSON = localDocs.appendingPathComponent(Self.fileName)
        let icloudJSON = Self.fileURL

        // Only migrate if local file exists and iCloud file doesn't
        guard FileManager.default.fileExists(atPath: localJSON.path),
              !FileManager.default.fileExists(atPath: icloudJSON.path),
              localJSON.path != icloudJSON.path else { return }

        do {
            // Copy references.json
            try FileManager.default.copyItem(at: localJSON, to: icloudJSON)

            // Copy ReferenceFiles directory
            let localRefFiles = localDocs.appendingPathComponent("ReferenceFiles")
            let icloudRefFiles = Self.referenceFilesDirectory
            if FileManager.default.fileExists(atPath: localRefFiles.path) {
                let files = try FileManager.default.contentsOfDirectory(at: localRefFiles, includingPropertiesForKeys: nil)
                for file in files {
                    let dest = icloudRefFiles.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.copyItem(at: file, to: dest)
                    }
                }
            }

            // Copy ReferencePhotos directory
            let localPhotos = localDocs.appendingPathComponent("ReferencePhotos")
            let icloudPhotos = Self.referencePhotosDirectory
            if FileManager.default.fileExists(atPath: localPhotos.path) {
                let files = try FileManager.default.contentsOfDirectory(at: localPhotos, includingPropertiesForKeys: nil)
                for file in files {
                    let dest = icloudPhotos.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.copyItem(at: file, to: dest)
                    }
                }
            }

            print("[ReferencesStore] Migrated local references to iCloud")
        } catch {
            print("[ReferencesStore] Migration error: \(error)")
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
