import Foundation
import OSLog

private let syncLogger = Logger(subsystem: "com.wookey.app", category: "sync")

/// Serialized, coordinated I/O runs off the main actor. iCloud owns network transfer.
actor SyncFolderIO {
    struct Scan: Sendable {
        var backups: [SyncBackup] = []
        /// Files that could not be used (damaged, mismatched name). Logged and skipped.
        var skipped = 0
        /// At least one version was written by a newer app with an unknown schema.
        var requiresUpdate = false
    }

    private enum Decoded {
        case backup(SyncBackup)
        case invalid
        case newer
    }

    private struct CacheKey: Hashable {
        var modified: Date?
        var size: Int?
    }

    /// Backups are immutable, so a decoded file is reused until its date or size changes.
    private var decodedCache: [URL: (key: CacheKey, value: Decoded)] = [:]
    private var fingerprints: [UUID: String] = [:]

    func pruneLocalBackups(in folder: URL, expiringThrough cutoff: Date) throws -> [SyncBackup] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try readBackups(in: folder, expiringThrough: cutoff).backups
    }

    func read(_ folder: URL) throws -> [SyncBackup] {
        try scan(folder).backups
    }

    func scan(_ folder: URL) throws -> Scan {
        try readBackups(in: folder, expiringThrough: nil)
    }

    /// Delete old shared versions. Missing files are ignored; another Mac may have pruned them.
    func remove(_ ids: [UUID], in folder: URL) throws {
        for id in ids {
            let url = folder.appendingPathComponent("\(id.uuidString).wookeybackup")
            try removeBackup(at: url)
            decodedCache[url.standardizedFileURL] = nil
            fingerprints[id] = nil
        }
    }

    private func readBackups(in folder: URL, expiringThrough cutoff: Date?) throws -> Scan {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        let placeholders = urls.filter { $0.lastPathComponent.hasSuffix(".wookeybackup.icloud") }
        if !placeholders.isEmpty {
            for placeholder in placeholders {
                let name = String(placeholder.lastPathComponent.dropFirst().dropLast(".icloud".count))
                try? FileManager.default.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            }
            throw SyncError.missingFile
        }
        var scan = Scan()
        for url in urls where url.pathExtension == "wookeybackup" {
            let cloud = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = cloud.ubiquitousItemDownloadingStatus, status != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                throw SyncError.missingFile
            }
            switch decode(url) {
            case .backup(let backup):
                if let cutoff, backup.createdAt <= cutoff {
                    try removeBackup(at: url)
                    decodedCache[url.standardizedFileURL] = nil
                } else {
                    scan.backups.append(backup)
                }
            case .invalid: scan.skipped += 1
            case .newer: scan.requiresUpdate = true
            }
        }
        let present = Set(urls.map(\.standardizedFileURL))
        decodedCache = decodedCache.filter { $0.key.deletingLastPathComponent() != folder.standardizedFileURL || present.contains($0.key) }
        return scan
    }

    private func decode(_ url: URL) -> Decoded {
        let standardized = url.standardizedFileURL
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = CacheKey(modified: values?.contentModificationDate, size: values?.fileSize)
        if let cached = decodedCache[standardized], cached.key == key { return cached.value }
        var coordinationError: NSError?
        var outcome: Result<SyncBackup, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            outcome = Result {
                let values = try readable.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? Int.max) <= SyncPayload.maximumBytes * 2 else { throw SyncError.invalidArchive }
                let backup = try SyncBackup.decode(Data(contentsOf: readable))
                guard readable.deletingPathExtension().lastPathComponent == backup.id.uuidString else { throw SyncError.invalidArchive }
                return backup
            }
        }
        let decoded: Decoded
        switch outcome {
        case .success(let backup)?:
            decoded = .backup(backup)
        case .failure(let error)? where (error as? SyncError) == .requiresUpdate:
            syncLogger.notice("Skipping backup from a newer app version: \(url.lastPathComponent, privacy: .public)")
            decoded = .newer
        case .failure(let error)?:
            syncLogger.error("Skipping unreadable backup \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            decoded = .invalid
        case nil:
            syncLogger.error("Skipping uncoordinated backup \(url.lastPathComponent, privacy: .public): \(coordinationError?.localizedDescription ?? "unknown", privacy: .public)")
            // A coordination failure may be transient; retry it on the next pass.
            return .invalid
        }
        decodedCache[standardized] = (key, decoded)
        return decoded
    }

    private func removeBackup(at url: URL) throws {
        var coordinationError: NSError?
        var deletionError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { writable in
            do { try FileManager.default.removeItem(at: writable) }
            catch let error as CocoaError where error.code == .fileNoSuchFile {}
            catch { deletionError = error }
        }
        if let error = coordinationError ?? deletionError { throw error }
    }

    func write(_ backup: SyncBackup, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(backup.id.uuidString).wookeybackup")
        let data = try backup.encoded()
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { writable in
            do {
                if FileManager.default.fileExists(atPath: writable.path) {
                    guard try Data(contentsOf: writable) == data else { throw SyncError.invalidArchive }
                } else { try data.write(to: writable, options: .atomic) }
            } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    func capture(_ state: PersistedState, root: URL) throws -> SyncPayload {
        try SyncPayload.capture(state: state, root: root)
    }

    func fingerprint(_ payload: SyncPayload) throws -> String { try payload.fingerprint }

    /// Backups are immutable by id, so their fingerprints are computed once.
    func fingerprint(of backup: SyncBackup) throws -> String {
        if let cached = fingerprints[backup.id] { return cached }
        let value = try backup.payload.fingerprint
        fingerprints[backup.id] = value
        return value
    }

    /// A cheap stand-in for the full fingerprint: the configuration plus the modification date
    /// and size of every file it references. If unchanged, no file has to be read or hashed.
    func signature(_ state: PersistedState, root: URL) throws -> String {
        var data = try SyncPayload.encoder().encode(state)
        func append(_ url: URL) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
            data.append(Data("\n\(url.path)|\(modified)|\(values?.fileSize ?? -1)".utf8))
        }
        let templates = root.appendingPathComponent("Templates", isDirectory: true)
        for template in state.templates { append(templates.appendingPathComponent(template.fileName)) }
        for workflow in state.workflows {
            for action in workflow.actions {
                switch action {
                case .openFile(let path): append(URL(fileURLWithPath: path))
                case .pasteFiles(let paths), .pasteImages(let paths): paths.forEach { append(URL(fileURLWithPath: $0)) }
                default: break
                }
            }
        }
        return SyncPayload.digest(data)
    }

    func prepare(_ payload: SyncPayload, root: URL) throws -> PersistedState {
        try WookeyStore.prepareBackup(payload, rootURL: root)
    }
}
