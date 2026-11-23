import AppKit
import Foundation
import Observation

@MainActor @Observable
public final class ICloudSyncService {
    public private(set) var isEnabled = false
    public private(set) var isBusy = false
    public private(set) var status = "꺼짐 · 설정은 이 Mac에만 저장됩니다."
    public private(set) var errorMessage: String?
    public private(set) var versions: [SyncBackup] = []
    public private(set) var conflicts: [SyncBackup] = []
    public private(set) var pendingVersion: SyncBackup?
    public private(set) var lastChecked: Date?
    public private(set) var folderName = ""
    public var resolutionParents: [UUID] { observedHeads }
    @ObservationIgnored public var canApply: () -> Bool = { true }
    @ObservationIgnored public var onApply: (() -> Void)?
    @ObservationIgnored private let store: WookeyStore
    @ObservationIgnored private let io = SyncFolderIO()
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var scopedAccess = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var nextBackupMaintenance = Date.distantPast
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observedHeads: [UUID] = []
    @ObservationIgnored private var editingSessions: Set<UUID> = []
    @ObservationIgnored private var stagedBackup: (fingerprint: String, backup: SyncBackup)?
    @ObservationIgnored private var metadata = Metadata()
    /// The last full fingerprint of local state, keyed by a cheap signature of the config and file dates.
    @ObservationIgnored private var localFingerprint: (signature: String, fingerprint: String)?
    /// When a recent version's parent was first seen missing from the folder.
    @ObservationIgnored private var missingParentsSince: Date?
    private var metadataURL: URL { store.storageURL.appendingPathComponent("sync-device.json") }
    private var backupsURL: URL { store.storageURL.appendingPathComponent("Backups", isDirectory: true) }
    /// The same window applies to local restore backups and to old shared history.
    private var backupCutoff: Date { Date().addingTimeInterval(-30 * 24 * 60 * 60) }
    /// How long a missing parent may still be "downloading" before it is treated as deleted
    /// (for example after the user removed old versions in Finder).
    @ObservationIgnored var missingParentGracePeriod: TimeInterval = 5 * 60

    private struct Metadata: Codable {
        var bookmark: Data?
        var enabled = false
        var parents: [UUID] = []
        var fingerprint: String?
        // Deliberately avoid the user's computer name or account name.
        var device = "Mac-" + UUID().uuidString.prefix(6)
    }

    public init(store: WookeyStore) {
        self.store = store
        store.onSave = { [weak self] in self?.generation += 1 }
    }

    public func setEditing(_ editing: Bool, session: UUID) {
        if editing { editingSessions.insert(session) } else { editingSessions.remove(session) }
    }

    public func createBackup() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let capturedGeneration = generation
            let original = try SyncPayload.encoder().encode(store.state)
            let payload = try await io.capture(store.state, root: store.storageURL)
            guard capturedGeneration == generation,
                  try SyncPayload.encoder().encode(store.state) == original else { throw SyncError.busy }
            try await io.write(SyncBackup(payload: payload, device: metadata.device), folder: backupsURL)
            await refreshBackups()
            errorMessage = nil
            status = "이 Mac에 복원용 백업을 저장했습니다."
        } catch { errorMessage = error.localizedDescription }
    }

    public func start() {
        guard timer == nil else { return }
        nextBackupMaintenance = .distantPast
        do {
            if FileManager.default.fileExists(atPath: metadataURL.path) {
                metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
            }
            if metadata.enabled, let bookmark = metadata.bookmark {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
                scopedAccess = url.startAccessingSecurityScopedResource()
                folder = url; folderName = url.lastPathComponent; isEnabled = true
                if stale {
                    // The folder still resolves (e.g. it was moved or renamed); refresh the grant.
                    var next = metadata
                    next.bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    try saveMetadata(next); metadata = next
                }
            }
        } catch { errorMessage = "동기화 폴더를 다시 연결해 주세요. \(error.localizedDescription)" }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.maintainBackupsIfDue()
                await self?.synchronize()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Call only after an explicit opt-in and a native folder-picker grant.
    public func connect(to selected: URL) async {
        await connect(to: selected, requireICloud: true)
    }

    // Test seam: production always requires a user-selected ubiquitous directory.
    func connect(to selected: URL, requireICloud: Bool) async {
        guard !isBusy else { return }
        let accessed = selected.startAccessingSecurityScopedResource()
        do {
            let values = try selected.resourceValues(forKeys: [.isUbiquitousItemKey, .isDirectoryKey])
            guard (!requireICloud || values.isUbiquitousItem == true), values.isDirectory == true else { throw SyncError.notCloudFolder }
            let bookmark = try selected.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            var next = Metadata()
            next.bookmark = bookmark; next.enabled = true; next.device = metadata.device
            try saveMetadata(next)
            if scopedAccess { folder?.stopAccessingSecurityScopedResource() }
            metadata = next; folder = selected; scopedAccess = accessed
            folderName = selected.lastPathComponent; isEnabled = true
            conflicts = []; pendingVersion = nil; observedHeads = []; stagedBackup = nil; errorMessage = nil
            await synchronize()
        } catch {
            if accessed { selected.stopAccessingSecurityScopedResource() }
            errorMessage = error.localizedDescription
        }
    }

    public func disconnect() {
        guard !isBusy else { return }
        do {
            var next = metadata; next.enabled = false; next.bookmark = nil
            try saveMetadata(next)
            metadata = next; isEnabled = false
            if scopedAccess { folder?.stopAccessingSecurityScopedResource() }
            folder = nil; scopedAccess = false; conflicts = []; pendingVersion = nil
            status = "꺼짐 · 기존 설정과 백업은 삭제하지 않았습니다."
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func synchronize() async {
        guard isEnabled, let folder, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let recovering = store.needsRecovery
            // A failed save means memory and disk disagree; publish nothing until that is fixed.
            // During recovery the error describes the recovery itself, and nothing is published.
            guard recovering || store.lastPersistenceError == nil else { throw SyncError.invalidArchive }
            let capturedGeneration = generation
            let snapshot = store.state
            let capturedState = try SyncPayload.encoder().encode(snapshot)
            var local: SyncPayload?
            var fingerprint = metadata.fingerprint
            if !recovering {
                let signature = try await io.signature(snapshot, root: store.storageURL)
                if let cached = localFingerprint, cached.signature == signature {
                    fingerprint = cached.fingerprint
                } else {
                    let captured = try await io.capture(snapshot, root: store.storageURL)
                    let value = try await io.fingerprint(captured)
                    local = captured; fingerprint = value
                    localFingerprint = (signature, value)
                }
            } else if !metadata.parents.isEmpty || metadata.fingerprint != nil {
                // The unreadable configuration is not a descendant of shared history. If the user
                // later keeps it, it is published as a separate version for every Mac to choose.
                var next = metadata; next.parents = []; next.fingerprint = nil
                try saveMetadata(next); metadata = next
                fingerprint = nil
            }
            guard generation == capturedGeneration,
                  try SyncPayload.encoder().encode(store.state) == capturedState else { return }
            let publishesLocal = !recovering && fingerprint != metadata.fingerprint
            if publishesLocal, let fingerprint, stagedBackup?.fingerprint != fingerprint {
                let payload: SyncPayload
                if let local { payload = local } else { payload = try await io.capture(snapshot, root: store.storageURL) }
                let backup = SyncBackup(payload: payload, parents: metadata.parents, device: metadata.device)
                try await io.write(backup, folder: backupsURL)
                stagedBackup = (fingerprint, backup)
            }
            let scan = try await io.scan(folder)
            guard !scan.requiresUpdate else {
                errorMessage = SyncError.requiresUpdate.localizedDescription
                status = "앱 업데이트가 필요합니다 · 이 Mac의 설정은 유지됩니다."
                await refreshBackups()
                return
            }
            var remote = scan.backups
            if publishesLocal, let backup = stagedBackup?.backup {
                try await io.write(backup, folder: folder)
                if !remote.contains(where: { $0.id == backup.id }) { remote.append(backup) }
                var next = metadata
                next.parents = [backup.id]; next.fingerprint = fingerprint
                try saveMetadata(next); metadata = next
                stagedBackup = nil
            }
            let cutoff = backupCutoff
            // An absent ancestor may still be downloading; don't resolve incomplete history right away.
            // Parents of old versions were pruned on purpose. After a grace period, a missing parent
            // is treated as deleted (for example, removed in Finder) rather than waited on forever.
            let ids = Set(remote.map(\.id))
            let waiting = remote.contains { $0.createdAt > cutoff && $0.parents.contains { !ids.contains($0) } }
            if waiting {
                let since = missingParentsSince ?? Date()
                missingParentsSince = since
                if Date().timeIntervalSince(since) < missingParentGracePeriod {
                    status = "이전 버전의 다운로드를 기다리는 중입니다."; return
                }
            } else {
                missingParentsSince = nil
            }
            let heads = SyncBackup.heads(in: remote)
            try SyncBackup.validateGraph(remote.map { backup in
                var backup = backup; backup.parents.removeAll { !ids.contains($0) }; return backup
            })
            // Shared history otherwise grows forever. Skip pruning while any file is unreadable:
            // its links are unknown, so removing a possible ancestor could create a false head.
            if scan.skipped == 0 {
                let prunable = SyncBackup.prunable(in: remote, olderThan: cutoff).map(\.id)
                if !prunable.isEmpty {
                    try await io.remove(prunable, in: folder)
                    remote.removeAll { prunable.contains($0.id) }
                }
            }
            for head in heads where head.createdAt > cutoff { try await io.write(head, folder: backupsURL) }
            observedHeads = heads.map(\.id)
            conflicts = heads.count > 1 ? heads : []
            pendingVersion = nil
            if heads.count > 1 {
                status = "서로 다른 설정이 있습니다. 사용할 버전을 선택해 주세요."
            } else if recovering {
                pendingVersion = heads.first
                status = heads.isEmpty
                    ? "설정 파일 복구가 필요합니다. 새로 시작을 선택하면 이 Mac의 설정을 동기화합니다."
                    : "설정 파일 복구가 필요합니다. iCloud의 설정을 적용하거나 새로 시작을 선택해 주세요."
            } else if let head = heads.first, try await io.fingerprint(of: head) != metadata.fingerprint {
                pendingVersion = head
                if !NSApplication.shared.isActive && editingSessions.isEmpty && canApply() && generation == capturedGeneration,
                   try SyncPayload.encoder().encode(store.state) == capturedState {
                    try await apply(head, parents: [head.id], publish: false, automatic: true)
                } else {
                    status = "다른 Mac의 설정이 도착했습니다. 편집·실행이 끝나면 적용합니다."
                }
            } else {
                if let head = heads.first {
                    var next = metadata; next.parents = [head.id]
                    try saveMetadata(next); metadata = next
                }
                status = "폴더 확인 완료 · 인터넷 전송은 iCloud Drive가 처리합니다."
            }
            lastChecked = Date(); errorMessage = nil
            await refreshBackups()
        } catch {
            errorMessage = error.localizedDescription
            status = "동기화 대기 · 이 Mac의 설정은 유지됩니다."
            await refreshBackups()
        }
    }

    public func restore(_ backup: SyncBackup, resolving parents: [UUID]? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard canApply() else { throw SyncError.busy }
            // Resolve only versions actually shown to the user. Unseen arrivals remain concurrent.
            try await apply(backup, parents: parents ?? observedHeads, publish: isEnabled)
            conflicts = []; pendingVersion = nil; errorMessage = nil
            await refreshBackups()
        } catch { errorMessage = error.localizedDescription }
    }

    private func apply(_ backup: SyncBackup, parents: [UUID], publish: Bool, automatic: Bool = false) async throws {
        guard canApply() else { throw SyncError.busy }
        guard editingSessions.isEmpty else { throw SyncError.editing }
        let original = try SyncPayload.encoder().encode(store.state)
        let capturedGeneration = generation
        let current = try await io.capture(store.state, root: store.storageURL)
        let fingerprint = try await io.fingerprint(of: backup)
        try await io.write(SyncBackup(payload: current, device: metadata.device), folder: backupsURL)
        if backup.createdAt > backupCutoff { try await io.write(backup, folder: backupsURL) }
        let imported = try await io.prepare(backup.payload, root: store.storageURL)
        do {
            guard canApply(), capturedGeneration == generation,
                  try SyncPayload.encoder().encode(store.state) == original else { throw SyncError.busy }
            guard editingSessions.isEmpty, !automatic || !NSApplication.shared.isActive else { throw SyncError.editing }
            try store.commitImportedState(imported)
        } catch {
            // Discard this transaction's prepared files; the current state does not reference them.
            store.removeUnreferencedSyncFiles()
            throw error
        }
        generation += 1
        onApply?()
        // Leave metadata untouched on a failed write: the next check preserves it as a local edit.
        var next = metadata
        if publish, let folder {
            let resolved = SyncBackup(payload: backup.payload, parents: parents, device: metadata.device)
            try await io.write(resolved, folder: backupsURL)
            try await io.write(resolved, folder: folder)
            next.parents = [resolved.id]
        } else { next.parents = parents }
        next.fingerprint = fingerprint
        try saveMetadata(next); metadata = next
        stagedBackup = nil
        pendingVersion = nil
        status = "설정을 적용했습니다. 앱 설치·권한·모니터 연결은 이 Mac에서 확인해 주세요."
    }

    public func refreshBackups() async {
        nextBackupMaintenance = Date().addingTimeInterval(60 * 60)
        do {
            let remaining = try await io.pruneLocalBackups(in: backupsURL, expiringThrough: backupCutoff)
            versions = remaining.sorted { $0.createdAt > $1.createdAt }
        } catch { errorMessage = "백업 목록을 읽거나 정리하지 못했습니다: \(error.localizedDescription)" }
    }

    private func maintainBackupsIfDue() async {
        guard !isBusy, Date() >= nextBackupMaintenance else { return }
        await refreshBackups()
    }

    private func saveMetadata(_ value: Metadata) throws {
        try FileManager.default.createDirectory(at: store.storageURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: metadataURL, options: .atomic)
    }
}
