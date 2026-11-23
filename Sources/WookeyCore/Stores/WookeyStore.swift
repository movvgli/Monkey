import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class WookeyStore {
    public private(set) var state = PersistedState()
    public private(set) var lastPersistenceError: String?
    /// Set when config.json could not be read. Until a synced version is applied or the user
    /// explicitly starts fresh (`acknowledgeRecovery()`), the empty state must not be published
    /// to other Macs. Persisted with a marker file so it survives relaunches.
    public private(set) var needsRecovery = false
    @ObservationIgnored public var onSave: (() -> Void)?
    public var storageURL: URL { rootURL }

    public var workflows: [Workflow] {
        get { state.workflows }
        set { state.workflows = newValue }
    }

    public var templates: [RichTemplate] {
        get { state.templates }
        set { state.templates = newValue }
    }

    public var layouts: [WindowLayout] {
        get { state.layouts }
        set { state.layouts = newValue }
    }

    public var applicationShortcuts: [ApplicationShortcut] {
        get { state.applicationShortcuts }
        set { state.applicationShortcuts = newValue }
    }

    public var searchShortcut: ShortcutGesture {
        get { state.searchShortcut ?? .defaultSearch }
        set { state.searchShortcut = newValue }
    }

    private let rootURL: URL
    private let stateURL: URL
    private let templatesURL: URL
    private let recoveryMarkerURL: URL
    /// False when the unreadable config.json could not be preserved; saving would destroy it.
    private var canOverwriteState = true
    private var recoveryMessage: String?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL? = nil) {
        let baseURL = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wookey", isDirectory: true)
        self.rootURL = baseURL
        self.stateURL = baseURL.appendingPathComponent("config.json")
        self.templatesURL = baseURL.appendingPathComponent("Templates", isDirectory: true)
        self.recoveryMarkerURL = baseURL.appendingPathComponent("recovery-needed")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() {
        canOverwriteState = true
        needsRecovery = FileManager.default.fileExists(atPath: recoveryMarkerURL.path)
        recoveryMessage = needsRecovery
            ? "이전에 설정 파일이 손상되어 복구 확인이 필요합니다. iCloud의 설정을 적용하거나 새로 시작을 선택할 때까지 이 Mac의 설정을 동기화하지 않습니다."
            : nil
        do {
            try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: stateURL.path) else {
                state = PersistedState()
                lastPersistenceError = recoveryMessage
                return
            }
            let data = try Data(contentsOf: stateURL)
            let decoded = try decoder.decode(PersistedState.self, from: data)
            guard decoded.schemaVersion == 1 else {
                throw StoreError.unsupportedSchema(decoded.schemaVersion)
            }
            state = decoded
            lastPersistenceError = recoveryMessage
        } catch {
            state = PersistedState()
            needsRecovery = true
            do {
                let backupName = try backUpCorruptStateIfPresent()
                try Data().write(to: recoveryMarkerURL, options: .atomic)
                let kept = backupName.map { " 기존 파일은 \($0)에 보관했습니다." } ?? ""
                recoveryMessage = "설정을 불러오지 못해 빈 상태로 시작했습니다.\(kept) iCloud의 설정을 적용하거나 새로 시작을 선택할 때까지 이 Mac의 설정을 동기화하지 않습니다: \(error.localizedDescription)"
            } catch let backupError {
                canOverwriteState = false
                recoveryMessage = "설정을 불러오지 못했고 기존 파일을 백업하지도 못해 변경 사항을 저장하지 않습니다. Finder에서 config.json을 따로 복사해 주세요: \(error.localizedDescription) / \(backupError.localizedDescription)"
            }
            lastPersistenceError = recoveryMessage
        }
    }

    /// The user chose to keep the current (possibly empty) configuration after a load failure.
    /// The next sync publishes it as a new version alongside, not on top of, other Macs' history.
    public func acknowledgeRecovery() {
        guard needsRecovery else { return }
        if !canOverwriteState {
            // The unreadable file was never preserved; try once more before allowing overwrites.
            do { try backUpCorruptStateIfPresent() } catch {
                lastPersistenceError = recoveryMessage
                return
            }
            canOverwriteState = true
        }
        do {
            if FileManager.default.fileExists(atPath: recoveryMarkerURL.path) {
                try FileManager.default.removeItem(at: recoveryMarkerURL)
            }
        } catch {
            lastPersistenceError = "복구 상태를 해제하지 못했습니다: \(error.localizedDescription)"
            return
        }
        needsRecovery = false
        recoveryMessage = nil
        lastPersistenceError = nil
    }

    @discardableResult
    public func save() -> Bool {
        guard canOverwriteState else {
            lastPersistenceError = recoveryMessage
            return false
        }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
            lastPersistenceError = recoveryMessage
            onSave?()
            return true
        } catch {
            lastPersistenceError = "설정을 저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    public func addWorkflow(_ workflow: Workflow = Workflow()) -> UUID {
        state.workflows.append(workflow)
        save()
        return workflow.id
    }

    public func addTemplate() -> UUID {
        let template = RichTemplate()
        state.templates.append(template)
        let initial = NSAttributedString(string: "새 템플릿")
        saveTemplateDocument(initial, for: template.id)
        save()
        return template.id
    }

    public func addTemplate(name: String, document: NSAttributedString) -> UUID? {
        let template = RichTemplate(name: name, plainText: document.string)
        let url = templatesURL.appendingPathComponent(template.fileName)
        do {
            try writeTemplateDocument(document, to: url)
        } catch {
            lastPersistenceError = "템플릿을 저장하지 못했습니다: \(error.localizedDescription)"
            return nil
        }
        state.templates.append(template)
        guard save() else {
            state.templates.removeLast()
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return template.id
    }

    public func addLayout(_ layout: WindowLayout) -> Bool {
        state.layouts.append(layout)
        guard save() else {
            state.layouts.removeLast()
            return false
        }
        return true
    }

    public func setApplicationShortcut(
        bundleIdentifier: String,
        displayName: String,
        shortcut: ShortcutGesture
    ) {
        if let index = state.applicationShortcuts.firstIndex(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) {
            if shortcut.steps.isEmpty {
                state.applicationShortcuts.remove(at: index)
            } else {
                state.applicationShortcuts[index].displayName = displayName
                state.applicationShortcuts[index].shortcut = shortcut
            }
        } else if !shortcut.steps.isEmpty {
            state.applicationShortcuts.append(
                ApplicationShortcut(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    shortcut: shortcut
                )
            )
        }
        save()
    }

    public func deleteWorkflow(id: UUID) {
        state.workflows.removeAll { $0.id == id }
        removeActions {
            if case .runWorkflow(let workflowID) = $0 { return workflowID == id }
            return false
        }
        save()
    }

    public func deleteTemplate(id: UUID) {
        guard let template = state.templates.first(where: { $0.id == id }) else { return }
        state.templates.removeAll { $0.id == id }
        removeActions {
            if case .copyTemplate(let templateID, _) = $0 { return templateID == id }
            return false
        }
        try? FileManager.default.removeItem(at: templatesURL.appendingPathComponent(template.fileName))
        save()
    }

    public func deleteLayout(id: UUID) {
        state.layouts.removeAll { $0.id == id }
        removeActions {
            if case .applyLayout(let layoutID) = $0 { return layoutID == id }
            return false
        }
        save()
    }

    /// Drop every workflow action that refers to a deleted item.
    private func removeActions(where shouldRemove: (WorkflowAction) -> Bool) {
        for index in state.workflows.indices {
            state.workflows[index].actions.removeAll(where: shouldRemove)
        }
    }

    public func templateDocument(id: UUID) -> NSAttributedString {
        guard let template = state.templates.first(where: { $0.id == id }) else {
            return NSAttributedString()
        }
        let url = templatesURL.appendingPathComponent(template.fileName)
        guard let data = try? Data(contentsOf: url),
              let document = NSAttributedString(rtfd: data, documentAttributes: nil) else {
            return NSAttributedString(string: template.plainText)
        }
        return document
    }

    public func saveTemplateDocument(_ document: NSAttributedString, for id: UUID) {
        guard let index = state.templates.firstIndex(where: { $0.id == id }) else { return }
        do {
            let url = templatesURL.appendingPathComponent(state.templates[index].fileName)
            try writeTemplateDocument(document, to: url)
            state.templates[index].plainText = document.string
            save()
        } catch {
            lastPersistenceError = "템플릿을 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func writeTemplateDocument(_ document: NSAttributedString, to url: URL) throws {
        try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
        let range = NSRange(location: 0, length: document.length)
        guard let data = document.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else {
            throw StoreError.couldNotEncodeTemplate
        }
        try data.write(to: url, options: .atomic)
    }

    /// Copies an unreadable config.json aside. Returns the backup's file name, or nil when
    /// there was nothing to preserve. Throws if the copy failed, so callers never overwrite it.
    @discardableResult
    private func backUpCorruptStateIfPresent() throws -> String? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        // Relaunching before the user resolves recovery must not pile up copies of
        // the same unreadable file: reuse an identical earlier backup.
        let current = try Data(contentsOf: stateURL)
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
        for name in existing.sorted() where name.hasPrefix("config-corrupt-") && name.hasSuffix(".json") {
            if (try? Data(contentsOf: rootURL.appendingPathComponent(name))) == current { return name }
        }
        let formatter = ISO8601DateFormatter()
        let suffix = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "config-corrupt-\(suffix)-\(UUID().uuidString.prefix(8)).json"
        try FileManager.default.copyItem(at: stateURL, to: rootURL.appendingPathComponent(name))
        return name
    }

    /// Install a fully validated portable backup. The configuration is committed last;
    /// isolated asset names keep the previous configuration usable if any write fails.
    /// Test-only entry point; the app installs backups through `ICloudSyncService`.
    func installBackup(_ payload: SyncPayload) throws {
        let imported = try Self.prepareBackup(payload, rootURL: rootURL)
        do { try commitImportedState(imported) } catch {
            removeUnreferencedSyncFiles()
            throw error
        }
    }

    /// Preparation touches only new transaction-scoped assets. The sync service calls this
    /// off the UI actor and rechecks edits before committing the small configuration.
    nonisolated static func prepareBackup(_ payload: SyncPayload, rootURL: URL) throws -> PersistedState {
        try payload.validate()
        var imported = payload.state
        let templatesURL = rootURL.appendingPathComponent("Templates", isDirectory: true)
        let transaction = UUID().uuidString
        let assetsURL = rootURL.appendingPathComponent("SyncedAttachments", isDirectory: true)
            .appendingPathComponent(transaction, isDirectory: true)
        var writtenTemplates: [URL] = []
        do {
            try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: templatesURL, withIntermediateDirectories: true)
            var paths: [String: String] = [:]
            for (key, asset) in payload.assets {
                let directory = assetsURL.appendingPathComponent(key, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(asset.name)
                try asset.data.write(to: url, options: .atomic)
                paths[key] = url.path
            }
            for index in imported.templates.indices {
                let id = imported.templates[index].id.uuidString
                guard let data = payload.templateDocuments[id] else { throw SyncError.invalidArchive }
                let name = "\(id)-\(transaction).rtfd"
                let url = templatesURL.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                writtenTemplates.append(url)
                imported.templates[index].fileName = name
            }
            for index in imported.workflows.indices {
                imported.workflows[index].actions = try imported.workflows[index].actions.map { action in
                    switch action {
                    case .openFile(let key): return .openFile(path: try Self.assetPath(key, in: paths))
                    case .pasteFiles(let keys): return .pasteFiles(filePaths: try keys.map { try Self.assetPath($0, in: paths) })
                    case .pasteImages(let keys): return .pasteImages(filePaths: try keys.map { try Self.assetPath($0, in: paths) })
                    default: return action
                    }
                }
            }
            return imported
        } catch {
            // Only this transaction's files: no committed state references them yet.
            try? FileManager.default.removeItem(at: assetsURL)
            writtenTemplates.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    func commitImportedState(_ imported: PersistedState) throws {
        try encoder.encode(imported).write(to: stateURL, options: .atomic)
        state = imported
        // Applying a known-good version completes recovery from an unreadable config.json.
        try? FileManager.default.removeItem(at: recoveryMarkerURL)
        needsRecovery = false
        canOverwriteState = true
        recoveryMessage = nil
        lastPersistenceError = nil
        removeUnreferencedSyncFiles()
    }

    /// Delete synced attachment transactions and sync-written template documents that the
    /// current state no longer references. User-created templates (`<id>.rtfd`) are never touched.
    /// Call only while no backup is being prepared; the sync service serializes this with `isBusy`.
    func removeUnreferencedSyncFiles() {
        let files = FileManager.default
        let assetsRoot = rootURL.appendingPathComponent("SyncedAttachments", isDirectory: true)
        let prefix = assetsRoot.path + "/"
        var transactions = Set<String>()
        for workflow in state.workflows {
            for action in workflow.actions {
                let paths: [String]
                switch action {
                case .openFile(let path): paths = [path]
                case .pasteFiles(let list), .pasteImages(let list): paths = list
                default: paths = []
                }
                for path in paths where path.hasPrefix(prefix) {
                    if let transaction = path.dropFirst(prefix.count).split(separator: "/").first {
                        transactions.insert(String(transaction))
                    }
                }
            }
        }
        for folder in (try? files.contentsOfDirectory(atPath: assetsRoot.path)) ?? [] where !transactions.contains(folder) {
            try? files.removeItem(at: assetsRoot.appendingPathComponent(folder))
        }
        let referenced = Set(state.templates.map(\.fileName))
        for name in (try? files.contentsOfDirectory(atPath: templatesURL.path)) ?? []
        where !referenced.contains(name) && Self.isSyncTemplateName(name) {
            try? files.removeItem(at: templatesURL.appendingPathComponent(name))
        }
    }

    /// Matches `<template UUID>-<transaction UUID>.rtfd`, the names `prepareBackup` writes.
    nonisolated static func isSyncTemplateName(_ name: String) -> Bool {
        guard name.hasSuffix(".rtfd") else { return false }
        let stem = name.dropLast(".rtfd".count)
        guard stem.count == 73 else { return false }
        let template = stem.prefix(36), separator = stem.dropFirst(36).prefix(1), transaction = stem.suffix(36)
        return separator == "-" && UUID(uuidString: String(template)) != nil && UUID(uuidString: String(transaction)) != nil
    }

    nonisolated private static func assetPath(_ key: String, in paths: [String: String]) throws -> String {
        guard let path = paths[key] else { throw SyncError.invalidArchive }
        return path
    }
}

public enum StoreError: LocalizedError {
    case unsupportedSchema(Int)
    case couldNotEncodeTemplate

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "지원하지 않는 설정 버전입니다: \(version)"
        case .couldNotEncodeTemplate: "서식 템플릿을 RTFD로 변환할 수 없습니다."
        }
    }
}
