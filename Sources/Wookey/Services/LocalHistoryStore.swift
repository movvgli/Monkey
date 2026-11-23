import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

enum HistoryKind: String, CaseIterable {
    case clipboard
    case files = "images" // Retain the on-disk directory name for existing shelves.

    var title: String { self == .clipboard ? "클립보드" : "파일" }
    var symbol: String { self == .clipboard ? "doc.on.clipboard" : "folder" }
}

struct HistoryRetention: Codable, Equatable {
    enum Period: String, CaseIterable, Codable {
        case oneDay = "1일"
        case threeDays = "3일"
        case sevenDays = "7일"
        case custom = "직접 설정"
        case forever = "평생"
    }

    enum Unit: String, CaseIterable, Codable {
        case hours = "시간"
        case days = "일"
    }

    var period: Period = .sevenDays
    var amount = 24
    var unit: Unit = .hours

    var seconds: TimeInterval? {
        switch period {
        case .oneDay: 86_400
        case .threeDays: 3 * 86_400
        case .sevenDays: 7 * 86_400
        case .custom: Double(max(1, amount)) * (unit == .hours ? 3_600 : 86_400)
        case .forever: nil
        }
    }
}

@MainActor
@Observable
final class LocalHistoryStore {
    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let name: String
        let symbol: String
        let fileName: String
        var webURL: URL? = nil
    }

    private struct Settings: Codable {
        var clipboard = HistoryRetention()
        var files = HistoryRetention()
        var recordsClipboard = true

        enum CodingKeys: String, CodingKey {
            case clipboard, recordsClipboard
            case files = "images"
        }
    }

    private struct ClipboardPayload: Codable {
        let items: [[String: Data]]
    }

    private let root: URL
    private let clipboard: NSPasteboard
    private let files = FileManager.default
    private var settings = Settings()
    private var history: [HistoryKind: [Entry]] = [:]
    private(set) var errors: [HistoryKind: String] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pasteboardChangeCount = 0
    @ObservationIgnored private var nextPrune = Date.distantPast
    @ObservationIgnored private var outgoingFileDrags = Set<UUID>()
    @ObservationIgnored var onFileTakenFromShelf: ((UUID) -> Void)?

    init(root: URL, clipboard: NSPasteboard = .general) {
        self.root = root.appendingPathComponent("LocalHistory", isDirectory: true)
        self.clipboard = clipboard
    }

    var recordsClipboard: Bool { settings.recordsClipboard }
    var isDraggingFromShelf: Bool { !outgoingFileDrags.isEmpty }

    func beginFileDrag(_ id: UUID) { outgoingFileDrags.insert(id) }
    func endFileDrag(_ id: UUID, delivered: Bool) {
        outgoingFileDrags.remove(id)
        if delivered { onFileTakenFromShelf?(id) }
    }

    func entries(_ kind: HistoryKind) -> [Entry] { history[kind] ?? [] }

    func retention(_ kind: HistoryKind) -> HistoryRetention {
        kind == .clipboard ? settings.clipboard : settings.files
    }

    func start() {
        guard timer == nil else { return }
        if files.fileExists(atPath: settingsURL.path) {
            do {
                settings = try PropertyListDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
            } catch {
                report(error, kind: .clipboard, message: "보관 설정을 읽지 못했습니다")
                report(error, kind: .files, message: "보관 설정을 읽지 못했습니다")
            }
        }
        for kind in HistoryKind.allCases {
            let folders = (try? files.contentsOfDirectory(at: directory(kind), includingPropertiesForKeys: nil)) ?? []
            history[kind] = folders.compactMap { folder in
                let record = folder.appendingPathComponent("record.plist")
                guard let data = try? Data(contentsOf: record),
                      let entry = try? PropertyListDecoder().decode(Entry.self, from: data),
                      entry.id.uuidString == folder.lastPathComponent,
                      !["", ".", ".."].contains(entry.fileName),
                      (entry.fileName as NSString).lastPathComponent == entry.fileName,
                      files.fileExists(atPath: fileURL(for: entry, kind: kind).path) else { return nil }
                return entry
            }.sorted { $0.date > $1.date }
        }
        pasteboardChangeCount = clipboard.changeCount
        pruneExpired()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setRetention(_ value: HistoryRetention, for kind: HistoryKind) {
        var updated = settings
        if kind == .clipboard { updated.clipboard = value }
        else { updated.files = value }
        if save(updated, kind: kind) { pruneExpired() }
    }

    func setRecordsClipboard(_ enabled: Bool) {
        var updated = settings
        updated.recordsClipboard = enabled
        if save(updated, kind: .clipboard) {
            pasteboardChangeCount = clipboard.changeCount
        }
    }

    func fileURL(for entry: Entry, kind: HistoryKind) -> URL {
        directory(kind).appendingPathComponent(entry.id.uuidString, isDirectory: true)
            .appendingPathComponent(entry.fileName)
    }

    func restoreClipboard(_ entry: Entry) {
        do {
            let data = try Data(contentsOf: fileURL(for: entry, kind: .clipboard))
            let payload = try PropertyListDecoder().decode(ClipboardPayload.self, from: data)
            let items = payload.items.map { representations in
                let item = NSPasteboardItem()
                for (type, data) in representations {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                return item
            }
            clipboard.clearContents()
            let restored = clipboard.writeObjects(items)
            pasteboardChangeCount = clipboard.changeCount
            if restored { errors[.clipboard] = nil }
            else { errors[.clipboard] = "클립보드에 다시 복사하지 못했습니다." }
        } catch {
            report(error, kind: .clipboard, message: "클립보드에 다시 복사하지 못했습니다")
        }
    }

    func importFile(at url: URL) async -> Entry? {
        guard url.isFileURL else { return nil }
        let directory = directory(.files)
        do {
            let entry = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let source = url.resolvingSymlinksInPath()
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let name = url.lastPathComponent
                let fileName = name.caseInsensitiveCompare("record.plist") == .orderedSame ? "file.plist" : name
                let isImage = values.contentType?.conforms(to: .image) == true
                let entry = Entry(id: UUID(), date: Date(), name: name, symbol: isImage ? "photo" : "doc", fileName: fileName)
                try Self.write(entry, in: directory) { try FileManager.default.copyItem(at: source, to: $0) }
                return entry
            }.value
            record(entry, kind: .files)
            return entry
        } catch {
            report(error, kind: .files, message: "파일을 가져오지 못했습니다")
            return nil
        }
    }

    func importImage(data: Data, type: UTType) -> Entry? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let name = "이미지.\(type.preferredFilenameExtension ?? "img")"
        return insert(kind: .files, name: name, symbol: "photo", fileName: name) {
            try data.write(to: $0)
        }
    }

    func importLink(_ url: URL, title: String?) -> Entry? {
        guard Self.isWebURL(url) else { return nil }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString
        return insert(kind: .files, name: String(name.prefix(250)), symbol: "link", fileName: "link.webloc", webURL: url) {
            try PropertyListEncoder().encode(["URL": url.absoluteString]).write(to: $0)
        }
    }

    func openFile(_ entry: Entry) {
        let url = entry.webURL ?? fileURL(for: entry, kind: .files)
        guard entry.webURL.map(Self.isWebURL) ?? true, NSWorkspace.shared.open(url) else {
            errors[.files] = "‘\(entry.name)’을 열지 못했습니다."
            return
        }
        errors[.files] = nil
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }

    func remove(_ entry: Entry, kind: HistoryKind) {
        do {
            let folder = fileURL(for: entry, kind: kind).deletingLastPathComponent()
            if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
            history[kind]?.removeAll { $0.id == entry.id }
            if kind == .files { onFileTakenFromShelf?(entry.id) }
            errors[kind] = nil
        } catch {
            report(error, kind: kind, message: "기록을 삭제하지 못했습니다")
        }
    }

    func showFileImportError() {
        if errors[.files] == nil { errors[.files] = "일부 항목을 보관하지 못했습니다. 개별 파일과 웹 링크를 추가할 수 있습니다." }
    }

    private var settingsURL: URL { root.appendingPathComponent("settings.plist") }

    private func directory(_ kind: HistoryKind) -> URL {
        root.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    private func save(_ updated: Settings, kind: HistoryKind) -> Bool {
        do {
            try createRoot()
            try PropertyListEncoder().encode(updated).write(to: settingsURL, options: .atomic)
            settings = updated
            errors[kind] = nil
            return true
        } catch {
            report(error, kind: kind, message: "보관 설정을 저장하지 못했습니다")
            return false
        }
    }

    private func insert(
        kind: HistoryKind, name: String, symbol: String, fileName: String,
        webURL: URL? = nil, write: (URL) throws -> Void
    ) -> Entry? {
        let entry = Entry(id: UUID(), date: Date(), name: name, symbol: symbol, fileName: fileName, webURL: webURL)
        do {
            try Self.write(entry, in: directory(kind), content: write)
            record(entry, kind: kind)
            return entry
        } catch {
            report(error, kind: kind, message: "기록을 저장하지 못했습니다")
            return nil
        }
    }

    private nonisolated static func write(_ entry: Entry, in directory: URL, content: (URL) throws -> Void) throws {
        let files = FileManager.default
        try files.createDirectory(at: directory.deletingLastPathComponent(),
                                  withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let folder = directory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try content(folder.appendingPathComponent(entry.fileName))
            try PropertyListEncoder().encode(entry).write(to: folder.appendingPathComponent("record.plist"), options: .atomic)
        } catch {
            try? files.removeItem(at: folder)
            throw error
        }
    }

    private func record(_ entry: Entry, kind: HistoryKind) {
        history[kind, default: []].insert(entry, at: 0)
        errors[kind] = nil
    }

    private func report(_ error: Error, kind: HistoryKind, message: String) {
        errors[kind] = "\(message). \(error.localizedDescription)"
    }

    private func createRoot() throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    private func tick() {
        if Date() >= nextPrune { pruneExpired() }

        let change = clipboard.changeCount
        guard change != pasteboardChangeCount else { return }
        pasteboardChangeCount = change
        guard recordsClipboard, let items = clipboard.pasteboardItems,
              !items.contains(where: { item in
                  item.types.contains { Self.excludedClipboardTypes.contains($0.rawValue) }
              }) else { return }

        var payload: [[String: Data]] = []
        var remainingBytes = 32 * 1024 * 1024
        for item in items {
            var representations: [String: Data] = [:]
            for type in item.types where Self.supportsClipboardType(type) {
                guard let data = item.data(forType: type) else { continue }
                guard data.count <= remainingBytes else { return }
                remainingBytes -= data.count
                representations[type.rawValue] = data
            }
            if !representations.isEmpty { payload.append(representations) }
        }
        guard !payload.isEmpty, clipboard.changeCount == change else { return }
        let files = items.compactMap { $0.string(forType: .fileURL).flatMap(URL.init(string:)) }
        let text = items.lazy.compactMap { $0.string(forType: .string) ?? $0.string(forType: .URL) }.first
        let nonemptyText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = payload.contains { item in item.keys.contains { UTType($0)?.conforms(to: .image) == true } }
        let name = if !files.isEmpty {
            files.map(\.lastPathComponent).joined(separator: ", ")
        } else if let nonemptyText, !nonemptyText.isEmpty {
            nonemptyText
        } else {
            hasImage ? "복사한 이미지" : "복사한 내용"
        }
        let symbol = !files.isEmpty ? "doc" : hasImage ? "photo" : "text.alignleft"
        _ = insert(kind: .clipboard, name: String(name.prefix(250)), symbol: symbol, fileName: "contents.plist") {
            try PropertyListEncoder().encode(ClipboardPayload(items: payload)).write(to: $0)
        }
    }

    private func pruneExpired(now: Date = Date()) {
        nextPrune = now.addingTimeInterval(30)
        for kind in HistoryKind.allCases {
            guard let seconds = retention(kind).seconds else { continue }
            let cutoff = now.addingTimeInterval(-seconds)
            for entry in entries(kind).reversed() where entry.date <= cutoff && !outgoingFileDrags.contains(entry.id) {
                remove(entry, kind: kind)
            }
        }
    }

    private static let excludedClipboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"
    ]

    private static func supportsClipboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if [.string, .rtf, .rtfd, .html, .URL, .fileURL, .pdf, .png, .tiff].contains(type) { return true }
        return UTType(type.rawValue)?.conforms(to: .image) == true
    }
}
