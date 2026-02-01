//
//  iCloudSyncManager.swift
//  Second_EMRApp
//

import Foundation
import Combine

@MainActor
final class iCloudSyncManager: ObservableObject {

    static let shared = iCloudSyncManager()

    @Published var iCloudAvailable: Bool = false

    /// The resolved base directory: iCloud container Documents if available, else local Documents.
    let baseURL: URL

    private let containerID = "iCloud.com.magedkilada.Second-EMRApp"
    private var metadataQuery: NSMetadataQuery?
    private var changeHandlers: [String: () -> Void] = [:]

    // MARK: - Init

    private init() {
        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.magedkilada.Second-EMRApp") {
            let docsURL = containerURL.appendingPathComponent("Documents")
            try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            self.baseURL = docsURL
            self.iCloudAvailable = true
            print("[iCloud] Container available: \(docsURL.path)")
        } else {
            self.baseURL = localDocs
            self.iCloudAvailable = false
            print("[iCloud] Not available — using local Documents")
        }

        migrateLocalToiCloudIfNeeded()
    }

    // MARK: - Path Helpers

    func url(for filename: String) -> URL {
        baseURL.appendingPathComponent(filename)
    }

    func directoryURL(for subdirectory: String) -> URL {
        let dir = baseURL.appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Download Trigger

    /// Call before previewing an attachment to ensure it's been downloaded from iCloud.
    func ensureDownloaded(_ url: URL) {
        guard iCloudAvailable else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                print("[iCloud] Download trigger failed: \(error)")
            }
        }
    }

    // MARK: - Change Registration

    func registerForChanges(filename: String, handler: @escaping () -> Void) {
        changeHandlers[filename] = handler
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard iCloudAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
        self.metadataQuery = query
        print("[iCloud] Monitoring started")
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        metadataQuery?.disableUpdates()
        defer { metadataQuery?.enableUpdates() }

        guard let items = metadataQuery?.results as? [NSMetadataItem] else { return }

        for item in items {
            guard let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { continue }
            if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                resolveConflicts(for: url)
            }
            Task { @MainActor in
                changeHandlers[name]?()
            }
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        metadataQuery?.disableUpdates()
        defer { metadataQuery?.enableUpdates() }

        // Initial gather — trigger all handlers to pick up latest
        Task { @MainActor in
            for handler in changeHandlers.values {
                handler()
            }
        }
    }

    // MARK: - Conflict Resolution

    private func resolveConflicts(for url: URL) {
        guard let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflictVersions.isEmpty else { return }

        // Last-writer-wins: keep current, mark conflicts resolved
        for version in conflictVersions {
            version.isResolved = true
        }
        do {
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
        } catch {
            print("[iCloud] Conflict cleanup failed: \(error)")
        }
    }

    // MARK: - Migration (Local → iCloud, one-time)

    private func migrateLocalToiCloudIfNeeded() {
        guard iCloudAvailable else { return }

        let migrationKey = "iCloudMigrationCompleted_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let localDocs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fm = FileManager.default

        let jsonFiles = [
            "patients.json", "notes.json", "attachments.json", "vitals.json",
            "appointments.json", "references.json", "physicians.json"
        ]
        let directories = ["AttachmentFiles", "ReferenceFiles", "ReferencePhotos"]

        for file in jsonFiles {
            let src = localDocs.appendingPathComponent(file)
            let dst = baseURL.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { continue }
            guard !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
                print("[Migration] Copied \(file) to iCloud")
            } catch {
                print("[Migration] Failed \(file): \(error)")
            }
        }

        for dir in directories {
            let src = localDocs.appendingPathComponent(dir)
            let dst = baseURL.appendingPathComponent(dir)
            guard fm.fileExists(atPath: src.path) else { continue }
            guard !fm.fileExists(atPath: dst.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
                print("[Migration] Copied directory \(dir) to iCloud")
            } catch {
                print("[Migration] Failed directory \(dir): \(error)")
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[Migration] Complete")
    }
}
