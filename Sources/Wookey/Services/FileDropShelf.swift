import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WookeyCore

enum ShelfAfterDrop: String, CaseIterable {
    case hide, keep

    static let storageKey = "shelfAfterDrop"
    static let defaultValue = Self.keep

    var title: String { self == .hide ? L10n.text("즉시 숨기기") : L10n.text("유지하기") }
}

enum ShelfShakeSensitivity: String, CaseIterable {
    case low, normal, high

    static let storageKey = "shelfShakeSensitivity"
    static let defaultValue = Self.normal

    var title: String {
        switch self {
        case .low: L10n.text("낮음")
        case .normal: L10n.text("보통")
        case .high: L10n.text("높음")
        }
    }

    var minimumTravel: CGFloat {
        switch self {
        case .low: 40
        case .normal: 26
        case .high: 18
        }
    }
}

@MainActor
@Observable
final class FloatingShelfSession {
    static let mascotSize = NSSize(width: 148, height: 134)
    static let preferredBubbleWidth: CGFloat = 272
    static let singleItemBubbleWidth: CGFloat = 164
    static let cardHeight: CGFloat = 80
    static let cardSpacing: CGFloat = 8
    static let bubblePadding: CGFloat = 12
    static let headerHeight: CGFloat = 36
    nonisolated static let thoughtGutterWidth: CGFloat = 38

    var mascotFrame: NSRect
    var entries: [LocalHistoryStore.Entry] = [] {
        didSet { selection.retain(orderedIDs) }
    }
    private(set) var selection = ShelfSelection()
    var isExpanded = false
    var bubbleOnLeft = false
    var bubbleWidth: CGFloat = 0
    var bubbleHeight: CGFloat = 0
    var bubbleTopInset: CGFloat = 0
    var mascotTopInset: CGFloat = 0

    init(mascotFrame: NSRect) {
        self.mascotFrame = mascotFrame
    }

    private var orderedIDs: [UUID] { entries.map(\.id) }

    var columnCount: Int { bubbleWidth >= 234 ? 2 : 1 }

    func select(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
        selection.click(id, in: orderedIDs, extending: modifiers.contains(.shift), toggling: modifiers.contains(.command))
    }

    func entriesForDrag(from entry: LocalHistoryStore.Entry) -> [LocalHistoryStore.Entry] {
        if !selection.ids.contains(entry.id) { select(entry.id) }
        return entries.filter { selection.ids.contains($0.id) }
    }
}

struct ShelfSelection {
    private(set) var ids: Set<UUID> = []
    private var rangeAnchor: UUID?
    // Preserve selections that existed before the current range so reversing it shrinks cleanly.
    private var baseRangeSelection: Set<UUID>?

    mutating func click(_ id: UUID, in order: [UUID], extending: Bool, toggling: Bool) {
        guard let end = order.firstIndex(of: id) else { return }
        if extending, let rangeAnchor, let start = order.firstIndex(of: rangeAnchor) {
            let range = order[min(start, end)...max(start, end)]
            if toggling {
                if baseRangeSelection == nil { baseRangeSelection = ids }
                ids = (baseRangeSelection ?? []).union(range)
            } else {
                baseRangeSelection = nil
                ids = Set(range)
            }
            return
        }
        rangeAnchor = id
        baseRangeSelection = nil
        if toggling {
            if ids.remove(id) == nil { ids.insert(id) }
        } else {
            ids = [id]
        }
    }

    mutating func retain(_ order: [UUID]) {
        ids.formIntersection(order)
        baseRangeSelection?.formIntersection(order)
        if let rangeAnchor, !order.contains(rangeAnchor) {
            self.rangeAnchor = order.first { ids.contains($0) }
            baseRangeSelection = nil
        }
    }
}

struct FileDropTarget: NSViewRepresentable {
    let history: LocalHistoryStore

    func makeNSView(context: Context) -> FileDropView { FileDropView(history: history) }
    func updateNSView(_ nsView: FileDropView, context: Context) {}
}

@MainActor
@Observable
final class FileDropFeedback {
    struct Receipt {
        let id = UUID()
        let photo: CGImage?
        let symbol: String
    }

    var isTargeted = false
    var isReceiving = false
    var receipt: Receipt?
}

@MainActor
final class FileDropView: NSView {
    private let history: LocalHistoryStore
    private let onSaved: ([LocalHistoryStore.Entry]) -> Void
    private let feedback = FileDropFeedback()
    private var activeImports = 0
    private var pendingPromises = 0
    private var promiseDeadline: TimeInterval = 0
    var isImporting: Bool { activeImports > 0 || pendingPromises > 0 }
    private static let filePathTypes: [NSPasteboard.PasteboardType] = [.fileURL, .init("NSFilenamesPboardType")]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private static let shelfTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL] + imageTypes + promiseTypes
    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(
        history: LocalHistoryStore, shelf: FloatingShelfSession? = nil, onToggle: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}, onMove: @escaping (NSEvent) -> Void = { _ in },
        onSaved: @escaping ([LocalHistoryStore.Entry]) -> Void = { _ in }
    ) {
        self.history = history
        self.onSaved = onSaved
        super.init(frame: .zero)
        registerForDraggedTypes(Self.shelfTypes + [.string])
        guard let shelf else {
            setAccessibilityElement(true)
            setAccessibilityRole(.group)
            setAccessibilityLabel(L10n.text("우키에게 파일이나 링크를 놓는 드롭 영역"))
            return
        }
        let artwork = NSHostingView(rootView:
            FloatingShelfView(
                history: history, session: shelf, feedback: feedback,
                onToggle: onToggle, onClose: onClose, onMove: onMove
            )
            .modifier(WookeyThemeScope())
        )
        artwork.sizingOptions = []
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: topAnchor),
            artwork.bottomAnchor.constraint(equalTo: bottomAnchor),
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    static func hasFileDrag(on pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: promiseTypes) != nil { return true }
        guard pasteboard.availableType(from: filePathTypes) != nil else { return false }
        return !fileURLs(on: pasteboard).isEmpty
    }

    static func dropOperation(for pasteboard: NSPasteboard, allowed: NSDragOperation) -> NSDragOperation {
        let hasWebLink = !webLinks(on: pasteboard).isEmpty
        if allowed.contains(.copy),
           hasWebLink || pasteboard.availableType(from: imageTypes + promiseTypes) != nil || !fileURLs(on: pasteboard).isEmpty {
            return .copy
        }
        return allowed.contains(.link) && hasWebLink ? .link : []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = Self.dropOperation(for: sender.draggingPasteboard, allowed: sender.draggingSourceOperationMask)
        feedback.isTargeted = !operation.isEmpty
        return operation
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { feedback.isTargeted = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        feedback.isTargeted = false
        let pasteboard = sender.draggingPasteboard
        let links = Self.webLinks(on: pasteboard)
        guard sender.draggingSourceOperationMask.contains(.copy) else { return saveLinks(links) }
        let files = Self.fileURLs(on: pasteboard)
        if !files.isEmpty {
            beginImport()
            Task { await importFiles(files, links: links) }
            return true
        }
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self])?
            .compactMap { $0 as? NSFilePromiseReceiver } ?? []
        if !promises.isEmpty {
            return receive(promises)
        }
        for type in Self.imageTypes {
            guard let data = pasteboard.data(forType: type), let imageType = UTType(type.rawValue) else { continue }
            if let entry = history.importImage(data: data, type: imageType) {
                finishSaving([entry])
                return true
            }
        }
        return saveLinks(links)
    }

    private func saveLinks(_ links: [WebLink]) -> Bool {
        let saved = links.compactMap { history.importLink($0.url, title: $0.title) }
        finishSaving(saved)
        if saved.isEmpty || saved.count < links.count { history.showFileImportError() }
        return !saved.isEmpty
    }

    private struct WebLink {
        let url: URL
        let title: String?
    }

    private static func webLinks(on pasteboard: NSPasteboard) -> [WebLink] {
        let titleType = NSPasteboard.PasteboardType("public.url-name")
        var seen = Set<URL>()
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard item.string(forType: .fileURL) == nil,
                  let value = item.string(forType: .URL) ?? item.string(forType: .string),
                  let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  LocalHistoryStore.isWebURL(url),
                  seen.insert(url).inserted else { return nil }
            return WebLink(url: url, title: item.string(forType: titleType))
        }
    }

    private func importFiles(_ files: [URL], links: [WebLink]) async {
        var saved: [LocalHistoryStore.Entry] = []
        for file in files {
            if let entry = await history.importFile(at: file) { saved.append(entry) }
        }
        saved += links.compactMap { history.importLink($0.url, title: $0.title) }
        endImport()
        finishSaving(saved)
        if saved.count < files.count + links.count { history.showFileImportError() }
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?
            .compactMap { $0 as? URL } ?? []
        return urls.filter {
            (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private func receive(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            history.showFileImportError()
            return false
        }
        var count = 0
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: Self.promiseQueue) { [history, weak self] url, error in
                Task { @MainActor in
                    defer {
                        if error == nil, url.deletingLastPathComponent() == folder { try? files.removeItem(at: url) }
                    }
                    self?.beginImport()
                    self?.completePromise()
                    let entry = error == nil ? await history.importFile(at: url) : nil
                    self?.endImport()
                    if let entry {
                        self?.finishSaving([entry])
                    } else {
                        history.showFileImportError()
                    }
                }
            }
            count += max(1, receiver.fileNames.isEmpty ? receiver.fileTypes.count : receiver.fileNames.count)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { try? files.removeItem(at: folder) }
        if count > 0 {
            pendingPromises += count
            promiseDeadline = ProcessInfo.processInfo.systemUptime + 30
            feedback.isReceiving = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.expirePromises()
            }
        } else {
            history.showFileImportError()
        }
        return count > 0
    }

    private func completePromise() {
        pendingPromises = max(0, pendingPromises - 1)
        feedback.isReceiving = isImporting
    }

    private func expirePromises() {
        guard ProcessInfo.processInfo.systemUptime >= promiseDeadline else { return }
        pendingPromises = 0
        feedback.isReceiving = isImporting
    }

    private func beginImport() {
        activeImports += 1
        feedback.isReceiving = true
    }

    private func endImport() {
        activeImports -= 1
        feedback.isReceiving = isImporting
    }

    private func finishSaving(_ entries: [LocalHistoryStore.Entry]) {
        guard let entry = entries.last else { return }
        let photo = entry.symbol == "photo"
            ? historyImageThumbnail(at: history.fileURL(for: entry, kind: .files), maxPixelSize: 96) : nil
        feedback.receipt = FileDropFeedback.Receipt(photo: photo, symbol: entry.symbol)
        onSaved(entries)
    }
}

@MainActor
final class FileDropShelf {
    private let history: LocalHistoryStore
    private let pasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?
    private var panel: NSPanel?
    private var session: FloatingShelfSession?
    private var dragChangeCount = 0
    private var fileDragChangeCount: Int?
    private var shake = DragShake()
    private var tracking = false
    private var lastRelease: TimeInterval?
    private var moveStart: (pointer: NSPoint, origin: NSPoint)?

    private var behavior: ShelfAfterDrop {
        UserDefaults.standard.string(forKey: ShelfAfterDrop.storageKey).flatMap(ShelfAfterDrop.init(rawValue:))
            ?? ShelfAfterDrop.defaultValue
    }

    init(history: LocalHistoryStore) { self.history = history }

    func start() {
        guard timer == nil else { return }
        history.onFilesTakenFromShelf = { [weak self] ids in self?.takeFiles(ids) }
        dragChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        guard moveStart == nil else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if tracking {
                tracking = false
                lastRelease = now
                dragChangeCount = pasteboard.changeCount
                fileDragChangeCount = nil
            }
            let dropView = panel?.contentView as? FileDropView
            guard dropView?.isImporting != true else { return }
            let hasEntries = session?.entries.isEmpty == false
            if hasEntries, behavior == .keep { return }
            if let lastRelease, hasEntries || now >= lastRelease + 0.20 {
                close()
            }
            return
        }

        tracking = true
        guard !history.isDraggingFromShelf, panel == nil else { return }
        let change = pasteboard.changeCount
        // The drag pasteboard can still contain the previous drag after mouse-up.
        guard change != dragChangeCount else { return }
        let point = NSEvent.mouseLocation
        if fileDragChangeCount != change {
            guard FileDropView.hasFileDrag(on: pasteboard) else { return }
            fileDragChangeCount = change
            let stored = UserDefaults.standard.string(forKey: ShelfShakeSensitivity.storageKey)
            let sensitivity = stored.flatMap(ShelfShakeSensitivity.init(rawValue:)) ?? .defaultValue
            shake = DragShake(anchor: point, sensitivity: sensitivity)
            return
        }
        guard shake.sample(point, now: now) else { return }
        show(near: point)
    }

    private func show(near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let size = FloatingShelfSession.mascotSize
        let bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        let preferredX = point.x + 34 + size.width <= bounds.maxX ? point.x + 34 : point.x - size.width - 34
        let origin = NSPoint(x: min(max(preferredX, bounds.minX), bounds.maxX - size.width),
                             y: min(max(point.y - size.height / 2, bounds.minY), bounds.maxY - size.height))
        let mascotFrame = NSRect(origin: origin, size: size)
        let panel = ShelfPanel(contentRect: mascotFrame,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.text("우키 서랍")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        let session = FloatingShelfSession(mascotFrame: mascotFrame)
        self.session = session
        panel.contentView = FileDropView(
            history: history, shelf: session,
            onToggle: { [weak self] in self?.toggleExpanded() },
            onClose: { [weak self] in self?.close() },
            onMove: { [weak self] event in self?.move(with: event) },
            onSaved: { [weak self, weak session] entries in
                guard let self, let session, self.session === session else { return }
                session.entries.append(contentsOf: entries)
                if session.isExpanded { self.resize() }
            }
        )
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func takeFiles(_ ids: Set<UUID>) {
        guard let session, session.entries.contains(where: { ids.contains($0.id) }) else { return }
        session.entries.removeAll { ids.contains($0.id) }
        if session.entries.isEmpty, (panel?.contentView as? FileDropView)?.isImporting != true {
            close()
        } else if session.isExpanded {
            resize()
        }
    }

    private func toggleExpanded() {
        guard let session, !session.entries.isEmpty else { return }
        session.isExpanded.toggle()
        resize()
    }

    private func move(with event: NSEvent) {
        guard let panel, let session, event.window === panel else { return }
        switch event.type {
        case .leftMouseDown:
            guard let pointer = event.cgEvent?.location else { return }
            moveStart = (pointer, panel.frame.origin)
        case .leftMouseDragged:
            guard let moveStart, let pointer = event.cgEvent?.location else { return }
            let previous = panel.frame.origin
            // Quartz mouse coordinates stay fixed as the panel moves and increase downward.
            panel.setFrameOrigin(NSPoint(
                x: moveStart.origin.x + pointer.x - moveStart.pointer.x,
                y: moveStart.origin.y - (pointer.y - moveStart.pointer.y)
            ))
            session.mascotFrame = session.mascotFrame.offsetBy(
                dx: panel.frame.minX - previous.x,
                dy: panel.frame.minY - previous.y
            )
        case .leftMouseUp:
            guard moveStart != nil else { return }
            moveStart = nil
            resize()
        default:
            break
        }
    }

    private func resize() {
        guard moveStart == nil, let panel, let session else { return }
        var anchor = session.mascotFrame
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen ?? NSScreen.main
        else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        anchor.origin.x = max(bounds.minX, min(anchor.minX, bounds.maxX - anchor.width))
        anchor.origin.y = max(bounds.minY, min(anchor.minY, bounds.maxY - anchor.height))
        session.mascotFrame = anchor

        guard session.isExpanded else {
            session.mascotTopInset = 0
            panel.setFrame(anchor, display: true)
            return
        }

        let leftRoom = anchor.minX - bounds.minX
        let rightRoom = bounds.maxX - anchor.maxX
        let preferredWidth = session.entries.count == 1
            ? FloatingShelfSession.singleItemBubbleWidth : FloatingShelfSession.preferredBubbleWidth
        session.bubbleOnLeft = rightRoom < preferredWidth && leftRoom > rightRoom
        let available = session.bubbleOnLeft ? leftRoom : rightRoom
        session.bubbleWidth = max(0, min(available, preferredWidth))
        let rows = min(3, max(1, (session.entries.count + session.columnCount - 1) / session.columnCount))
        let gridHeight = CGFloat(rows) * FloatingShelfSession.cardHeight + CGFloat(rows - 1) * FloatingShelfSession.cardSpacing
        let bubbleHeight = min(bounds.height, gridHeight + FloatingShelfSession.headerHeight + FloatingShelfSession.bubblePadding + 4)
        let bubbleY = min(max(anchor.maxY + 42 - bubbleHeight, bounds.minY), bounds.maxY - bubbleHeight)
        let top = max(anchor.maxY, bubbleY + bubbleHeight)
        let bottom = min(anchor.minY, bubbleY)
        let x = session.bubbleOnLeft ? anchor.minX - session.bubbleWidth : anchor.minX
        session.bubbleHeight = bubbleHeight
        session.bubbleTopInset = top - bubbleY - bubbleHeight
        session.mascotTopInset = top - anchor.maxY
        panel.setFrame(NSRect(x: x, y: bottom, width: anchor.width + session.bubbleWidth, height: top - bottom), display: true)
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        session = nil
        moveStart = nil
        lastRelease = nil
    }

    private final class ShelfPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

struct DragShake {
    private let minimumTravel: CGFloat
    private var anchor: NSPoint
    private var extremum: CGFloat = 0
    private var legStarted: TimeInterval?
    private var horizontal = false
    private var direction: CGFloat = 1
    private var previousShake: TimeInterval?

    init(anchor: NSPoint = .zero, sensitivity: ShelfShakeSensitivity = .defaultValue) {
        self.anchor = anchor
        minimumTravel = sensitivity.minimumTravel
    }

    mutating func sample(_ point: NSPoint, now: TimeInterval) -> Bool {
        if let legStarted {
            if now - legStarted > 0.65 {
                anchor = point
                self.legStarted = nil
                return false
            }
            let distance = (horizontal ? point.x - anchor.x : point.y - anchor.y) * direction
            extremum = max(extremum, distance)
            if extremum - distance >= minimumTravel {
                anchor = point
                self.legStarted = nil
                if let previousShake, now - previousShake <= 1 {
                    self.previousShake = nil
                    return true
                }
                previousShake = now
            }
            return false
        }

        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        horizontal = abs(dx) >= abs(dy)
        let distance = horizontal ? dx : dy
        guard abs(distance) >= minimumTravel else { return false }
        direction = distance > 0 ? 1 : -1
        extremum = abs(distance)
        legStarted = now
        return false
    }
}
