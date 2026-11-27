import AppKit
import Foundation
import Testing
@testable import WookeyCore

@MainActor struct ICloudSyncTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WookeySyncTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func portableAttachmentsAndRichTemplateRoundTrip() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = WookeyStore(rootURL: root.appendingPathComponent("source")); source.load()
        let id = source.addTemplate()
        source.saveTemplateDocument(NSAttributedString(string: "동기화 테스트", attributes: [.link: URL(string: "https://example.com")!]), for: id)
        let attachment = root.appendingPathComponent("example.txt")
        try Data("file contents".utf8).write(to: attachment)
        source.workflows = [Workflow(name: "Test", actions: [.copyTemplate(templateID: id, mode: .copyAndPaste), .pasteFiles(filePaths: [attachment.path]), .pressKey(.enter)])]
        source.save()
        let payload = try SyncPayload.capture(state: source.state, root: source.storageURL)
        let backup = SyncBackup(payload: payload, device: "Test Mac")
        let data = try backup.encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains(root.path))
        let destination = WookeyStore(rootURL: root.appendingPathComponent("destination")); destination.load()
        try destination.installBackup(SyncBackup.decode(data).payload)
        #expect(destination.templateDocument(id: id).string == "동기화 테스트")
        #expect(destination.templateDocument(id: id).attribute(.link, at: 0, effectiveRange: nil) != nil)
        guard case .pasteFiles(let paths) = destination.workflows[0].actions[1] else { Issue.record("Missing attachment action"); return }
        #expect(paths[0] != attachment.path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: paths[0])) == Data("file contents".utf8))
        #expect(try SyncPayload.capture(state: destination.state, root: destination.storageURL).fingerprint == payload.fingerprint)
        let reloaded = WookeyStore(rootURL: destination.storageURL); reloaded.load()
        #expect(reloaded.workflows == destination.workflows)
    }

    @Test func invalidArchiveDoesNotReplaceExistingConfiguration() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load(); _ = store.addWorkflow()
        let original = try Data(contentsOf: root.appendingPathComponent("config.json"))
        var payload = try SyncPayload.capture(state: store.state, root: root)
        payload.assets["../escape"] = SyncAsset(name: "../escape", data: Data())
        #expect(throws: (any Error).self) { try store.installBackup(payload) }
        #expect(try Data(contentsOf: root.appendingPathComponent("config.json")) == original)
        #expect(store.workflows.count == 1)
    }

    @Test func missingAndOversizedFilesAreNotSilentlyOmitted() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load()
        store.workflows = [Workflow(actions: [.pasteImages(filePaths: [root.appendingPathComponent("missing.png").path])])]
        #expect(throws: (any Error).self) { try SyncPayload.capture(state: store.state, root: root) }
        let file = root.appendingPathComponent("large.dat")
        try Data(count: 21 * 1_024 * 1_024).write(to: file)
        store.workflows = [Workflow(actions: [.pasteFiles(filePaths: [file.path])])]
        #expect(throws: SyncError.self) { try SyncPayload.capture(state: store.state, root: root) }
    }

    @Test func concurrentEditsAreNotOrderedByDeviceClock() throws {
        let payload = SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:])
        let base = SyncBackup(payload: payload, device: "A")
        var left = SyncBackup(payload: payload, parents: [base.id], device: "A")
        left.createdAt = Date.distantFuture
        let right = SyncBackup(payload: payload, parents: [base.id], device: "B")
        let versions = [base, left, right]
        try SyncBackup.validateGraph(versions)
        #expect(Set(SyncBackup.heads(in: versions).map(\.id)) == [left.id, right.id])
        let resolved = SyncBackup(payload: payload, parents: [left.id, right.id], device: "A")
        #expect(SyncBackup.heads(in: versions + [resolved]).map(\.id) == [resolved.id])
    }

    @Test func cyclesAndMissingParentsAreRejected() throws {
        let payload = SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:])
        var a = SyncBackup(payload: payload, device: "A")
        let b = SyncBackup(payload: payload, parents: [a.id], device: "B")
        a.parents = [b.id]
        #expect(throws: SyncError.self) { try SyncBackup.validateGraph([a, b]) }
        #expect(throws: SyncError.self) { try SyncBackup.validateGraph([b]) }
    }

    @Test func twoMacConflictResolutionDeletionAndDisable() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let a = WookeyStore(rootURL: root.appendingPathComponent("A")); a.load()
        let b = WookeyStore(rootURL: root.appendingPathComponent("B")); b.load()
        a.workflows = [Workflow(name: "A setting")]; a.save()
        b.workflows = [Workflow(name: "B setting")]; b.save()
        let sa = ICloudSyncService(store: a), sb = ICloudSyncService(store: b)
        #expect(!sa.isEnabled)
        await sa.synchronize()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        await sa.connect(to: folder, requireICloud: false)
        await sb.connect(to: folder, requireICloud: false)
        #expect(sa.errorMessage == nil)
        #expect(sb.conflicts.count == 2)
        let selected = try #require(sb.conflicts.first { $0.payload.state.workflows.first?.name == "A setting" })
        await sb.restore(selected)
        #expect(b.workflows.first?.name == "A setting")
        await sa.synchronize()
        #expect(sa.conflicts.isEmpty)
        // A deletion is a new causal version rather than an ignored missing entry.
        b.deleteWorkflow(id: b.workflows[0].id)
        await sb.synchronize()
        sa.canApply = { false }
        await sa.synchronize()
        #expect(a.workflows.count == 1)
        let deletion = try #require(sa.pendingVersion)
        sa.canApply = { true }
        await sa.restore(deletion)
        #expect(a.workflows.isEmpty)
        #expect(!sa.versions.isEmpty)
        sa.disconnect()
        let count = try FileManager.default.contentsOfDirectory(atPath: folder.path).count
        _ = a.addWorkflow()
        await sa.synchronize()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == count)
        #expect(a.workflows.count == 1)
    }

    @Test func productionConnectionRejectsLocalFolder() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root.appendingPathComponent("store")); store.load()
        let sync = ICloudSyncService(store: store)
        await sync.connect(to: root)
        #expect(!sync.isEnabled)
        #expect(sync.errorMessage != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("store/sync-device.json").path))
    }

    @Test func unresolvedPlaceholderDoesNotAppearAsEmptyCloud() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent(".\(UUID()).wookeybackup.icloud"))
        await #expect(throws: (any Error).self) { try await SyncFolderIO().read(root) }
    }

    @Test func unseenConcurrentVersionSurvivesResolution() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = WookeyStore(rootURL: root.appendingPathComponent("store")); store.load(); _ = store.addWorkflow()
        let sync = ICloudSyncService(store: store)
        await sync.connect(to: folder, requireICloud: false)
        let io = SyncFolderIO()
        let initial = try #require(try await io.read(folder).first)
        var unseen = initial.payload; unseen.state.workflows[0].name = "Unseen edit"
        let incoming = SyncBackup(payload: unseen, parents: [initial.id], device: "Other Mac")
        try await io.write(incoming, folder: folder)
        await sync.restore(initial)
        let heads = SyncBackup.heads(in: try await io.read(folder))
        #expect(heads.count == 2)
        #expect(heads.contains { $0.id == incoming.id })
    }

    @Test func openEditorPreventsRestoreAndKeepsCurrentData() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load(); _ = store.addWorkflow()
        let sync = ICloudSyncService(store: store)
        let backup = SyncBackup(payload: SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:]), device: "Other")
        let session = UUID()
        sync.setEditing(true, session: session)
        await sync.restore(backup)
        #expect(store.workflows.count == 1)
        #expect(sync.errorMessage != nil)
        sync.setEditing(false, session: session)
        await sync.restore(backup)
        #expect(store.workflows.isEmpty)
        #expect(sync.errorMessage == nil)
        #expect(sync.versions.contains { $0.payload.state.workflows.count == 1 })
    }

    @Test func localBackupRetentionPrunesExpiredArchivesWithoutDeletingCloudHistory() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root.appendingPathComponent("local"))
        store.load()
        let local = store.storageURL.appendingPathComponent("Backups")
        let shared = root.appendingPathComponent("shared")
        let payload = try SyncPayload.capture(state: store.state, root: store.storageURL)
        var expired = SyncBackup(payload: payload, device: "Remote")
        expired.createdAt = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        var recent = SyncBackup(payload: payload, device: "Local")
        recent.createdAt = Date().addingTimeInterval(-29 * 24 * 60 * 60)
        let io = SyncFolderIO()
        try await io.write(expired, folder: local)
        try await io.write(recent, folder: local)
        try await io.write(expired, folder: shared)

        let sync = ICloudSyncService(store: store)
        await sync.refreshBackups()
        #expect(sync.versions.map(\.id) == [recent.id])
        #expect(try await io.read(local).map(\.id) == [recent.id])

        await sync.connect(to: shared, requireICloud: false)
        #expect(sync.conflicts.contains { $0.id == expired.id })
        #expect(!sync.versions.contains { $0.id == expired.id })
        #expect(try await io.read(shared).contains { $0.id == expired.id })
    }

    @Test func offlineBackupAndRestoreWithoutCloudOptIn() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load(); _ = store.addWorkflow()
        let sync = ICloudSyncService(store: store)
        await sync.createBackup()
        let backup = try #require(sync.versions.first)
        store.deleteWorkflow(id: store.workflows[0].id)
        await sync.restore(backup)
        #expect(store.workflows.count == 1)
        #expect(!sync.isEnabled)
    }

    @Test func failedAttachmentInstallationKeepsCommittedState() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load(); _ = store.addWorkflow()
        let original = try Data(contentsOf: root.appendingPathComponent("config.json"))
        // A file in place of the destination directory simulates an unwritable asset destination.
        try Data().write(to: root.appendingPathComponent("SyncedAttachments"))
        let payload = SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:])
        #expect(throws: (any Error).self) { try store.installBackup(payload) }
        #expect(try Data(contentsOf: root.appendingPathComponent("config.json")) == original)
        #expect(store.workflows.count == 1)
    }

    @Test func cloudHistoryIsImmutable() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let io = SyncFolderIO()
        var backup = SyncBackup(payload: SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:]), device: "A")
        try await io.write(backup, folder: root)
        backup.device = "Modified"
        await #expect(throws: (any Error).self) { try await io.write(backup, folder: root) }
        #expect(try await io.read(root).first?.device == "A")
    }

    @Test func preparingRestoreNeverOverwritesActiveTemplateFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load()
        let id = store.addTemplate()
        let old = try SyncPayload.capture(state: store.state, root: root)
        try store.installBackup(old)
        store.saveTemplateDocument(NSAttributedString(string: "New unsynced content"), for: id)
        let before = store.templates[0].fileName
        _ = try WookeyStore.prepareBackup(old, rootURL: root)
        #expect(store.templates[0].fileName == before)
        #expect(store.templateDocument(id: id).string == "New unsynced content")
    }

    private func emptyPayload() -> SyncPayload {
        SyncPayload(state: PersistedState(), templateDocuments: [:], assets: [:])
    }

    @Test func recoveryNeverPublishesEmptyStateButOffersRemoteVersion() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let a = WookeyStore(rootURL: root.appendingPathComponent("A")); a.load()
        a.workflows = [Workflow(name: "Keep me")]; a.save()
        let sa = ICloudSyncService(store: a)
        await sa.connect(to: folder, requireICloud: false)
        let published = try await SyncFolderIO().read(folder)
        #expect(published.count == 1)

        // The same Mac relaunches with an unreadable config, then edits before noticing.
        try Data("not-json".utf8).write(to: a.storageURL.appendingPathComponent("config.json"))
        let broken = WookeyStore(rootURL: a.storageURL); broken.load()
        #expect(broken.needsRecovery)
        _ = broken.addWorkflow(Workflow(name: "Scratch"))
        let sync = ICloudSyncService(store: broken)
        await sync.connect(to: folder, requireICloud: false)
        #expect(try await SyncFolderIO().read(folder).map(\.id) == published.map(\.id))
        let offered = try #require(sync.pendingVersion)
        #expect(broken.workflows.map(\.name) == ["Scratch"])
        await sync.restore(offered)
        #expect(!broken.needsRecovery)
        #expect(broken.workflows.map(\.name) == ["Keep me"])
    }

    @Test func acknowledgedRecoveryPublishesAsConcurrentVersion() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = WookeyStore(rootURL: root.appendingPathComponent("A")); store.load()
        store.workflows = [Workflow(name: "Original")]; store.save()
        let first = ICloudSyncService(store: store)
        await first.connect(to: folder, requireICloud: false)
        try Data("not-json".utf8).write(to: store.storageURL.appendingPathComponent("config.json"))
        let broken = WookeyStore(rootURL: store.storageURL); broken.load()
        let sync = ICloudSyncService(store: broken)
        await sync.connect(to: folder, requireICloud: false)
        broken.acknowledgeRecovery()
        await sync.synchronize()
        // The fresh state must not silently replace the original on other Macs.
        #expect(SyncBackup.heads(in: try await SyncFolderIO().read(folder)).count == 2)
        #expect(sync.conflicts.count == 2)
    }

    @Test func repeatedRestoresRemoveSupersededSyncFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root); store.load()
        let attachment = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: attachment)
        let templateID = store.addTemplate()
        store.workflows = [Workflow(actions: [.openFile(path: attachment.path)])]; store.save()
        let payload = try SyncPayload.capture(state: store.state, root: root)
        // A user-created template file the synced state doesn't know about must survive cleanup.
        let unrelated = root.appendingPathComponent("Templates/\(UUID().uuidString).rtfd")
        try Data("keep".utf8).write(to: unrelated)
        try store.installBackup(payload)
        try store.installBackup(payload)
        try store.installBackup(payload)
        let attachments = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("SyncedAttachments").path)
        #expect(attachments.count == 1)
        let templates = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Templates").path)
        #expect(templates.filter(WookeyStore.isSyncTemplateName).count == 1)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(store.templateDocument(id: templateID).string == L10n.text("새 템플릿"))
        guard case .openFile(let path) = store.workflows[0].actions[0] else { Issue.record("Missing action"); return }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("a".utf8))
    }

    @Test func pruningKeepsHeadsRecentVersionsAndTheirParents() throws {
        let old = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var a = SyncBackup(payload: emptyPayload(), device: "A"); a.createdAt = old
        var b = SyncBackup(payload: emptyPayload(), parents: [a.id], device: "A"); b.createdAt = old
        var c = SyncBackup(payload: emptyPayload(), parents: [b.id], device: "A"); c.createdAt = old
        let d = SyncBackup(payload: emptyPayload(), parents: [c.id], device: "A")
        var lonely = SyncBackup(payload: emptyPayload(), device: "B"); lonely.createdAt = old
        let pruned = Set(SyncBackup.prunable(in: [a, b, c, d, lonely], olderThan: cutoff).map(\.id))
        // c stays as d's parent and lonely as a head; a and b are old ancestors.
        #expect(pruned == [a.id, b.id])
    }

    @Test func synchronizePrunesOldSharedHistory() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        let io = SyncFolderIO()
        let old = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        var a = SyncBackup(payload: emptyPayload(), device: "Other"); a.createdAt = old
        var b = SyncBackup(payload: emptyPayload(), parents: [a.id], device: "Other"); b.createdAt = old
        var c = SyncBackup(payload: emptyPayload(), parents: [b.id], device: "Other"); c.createdAt = old
        for backup in [a, b, c] { try await io.write(backup, folder: folder) }
        let store = WookeyStore(rootURL: root.appendingPathComponent("A")); store.load()
        let sync = ICloudSyncService(store: store)
        sync.canApply = { false }
        await sync.connect(to: folder, requireICloud: false)
        let remaining = Set(try await io.read(folder).map(\.id))
        #expect(!remaining.contains(a.id))
        #expect(remaining.contains(c.id))
        #expect(sync.errorMessage == nil)
    }

    @Test func badAndNewerFilesAreSkippedIndividually() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let io = SyncFolderIO()
        let good = SyncBackup(payload: emptyPayload(), device: "A")
        try await io.write(good, folder: root)
        try Data("garbage".utf8).write(to: root.appendingPathComponent("\(UUID().uuidString).wookeybackup"))
        var scan = try await io.scan(root)
        #expect(scan.backups.map(\.id) == [good.id])
        #expect(scan.skipped == 1)
        #expect(!scan.requiresUpdate)
        try Data(#"{"schemaVersion":2,"somethingNew":true}"#.utf8)
            .write(to: root.appendingPathComponent("\(UUID().uuidString).wookeybackup"))
        scan = try await io.scan(root)
        #expect(scan.requiresUpdate)
        #expect(scan.backups.map(\.id) == [good.id])
    }

    @Test func newerSchemaInCloudShowsUpdateStatusWithoutPublishing() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":2}"#.utf8).write(to: folder.appendingPathComponent("\(UUID().uuidString).wookeybackup"))
        let store = WookeyStore(rootURL: root.appendingPathComponent("A")); store.load(); _ = store.addWorkflow()
        let sync = ICloudSyncService(store: store)
        await sync.connect(to: folder, requireICloud: false)
        #expect(sync.errorMessage == SyncError.requiresUpdate.localizedDescription)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
    }

    @Test func missingParentIsTreatedAsDeletedAfterGracePeriod() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        let io = SyncFolderIO()
        var payload = emptyPayload(); payload.state.workflows = [Workflow(name: "Remote")]
        let orphan = SyncBackup(payload: payload, parents: [UUID()], device: "Other")
        try await io.write(orphan, folder: folder)
        let store = WookeyStore(rootURL: root.appendingPathComponent("A")); store.load(); _ = store.addWorkflow()
        let sync = ICloudSyncService(store: store)
        await sync.connect(to: folder, requireICloud: false)
        #expect(sync.status == L10n.text("이전 버전의 다운로드를 기다리는 중입니다."))
        sync.missingParentGracePeriod = 0
        await sync.synchronize()
        #expect(!sync.status.contains("기다리는"))
        #expect(sync.conflicts.contains { $0.id == orphan.id })
    }
}
