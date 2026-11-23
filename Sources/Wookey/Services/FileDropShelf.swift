import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

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
    private let feedback = FileDropFeedback()
    private(set) var visibleUntil: TimeInterval = 0
    private var activeImports = 0
    var isImporting: Bool { activeImports > 0 }
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private static let shelfTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL] + imageTypes + promiseTypes
    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(history: LocalHistoryStore, floating: Bool = false) {
        self.history = history
        super.init(frame: .zero)
        let artwork = NSHostingView(rootView:
            FileDropSurface(feedback: feedback, floating: floating)
                .modifier(WookeyThemeScope())
                .allowsHitTesting(false)
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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("우키에게 파일이나 링크를 놓는 드롭 영역")
        registerForDraggedTypes(Self.shelfTypes + [.string])
    }

    required init?(coder: NSCoder) { nil }

    static func canShowShelf(for pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: shelfTypes) != nil || !webLinks(on: pasteboard).isEmpty
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
                showReceipt(entry)
                return true
            }
        }
        return saveLinks(links)
    }

    private func saveLinks(_ links: [WebLink]) -> Bool {
        let saved = links.compactMap { history.importLink($0.url, title: $0.title) }
        if let entry = saved.last { showReceipt(entry) }
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
        if let entry = saved.last { showReceipt(entry) }
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
        var receiving = false
        for receiver in receivers {
            let destination = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            guard (try? files.createDirectory(at: destination, withIntermediateDirectories: false)) != nil else { continue }
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: Self.promiseQueue) { [history, weak self] url, error in
                Task { @MainActor in
                    defer {
                        if url.deletingLastPathComponent() == destination { try? files.removeItem(at: url) }
                    }
                    self?.beginImport()
                    let entry = error == nil ? await history.importFile(at: url) : nil
                    self?.endImport()
                    if let entry {
                        self?.showReceipt(entry)
                    } else {
                        history.showFileImportError()
                    }
                }
            }
            receiving = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { try? files.removeItem(at: folder) }
        if receiving {
            feedback.isReceiving = true
            visibleUntil = ProcessInfo.processInfo.systemUptime + 2
        } else {
            history.showFileImportError()
        }
        return receiving
    }

    private func beginImport() {
        activeImports += 1
        feedback.isReceiving = true
    }

    private func endImport() {
        activeImports -= 1
        feedback.isReceiving = isImporting
    }

    private func showReceipt(_ entry: LocalHistoryStore.Entry) {
        let photo = entry.symbol == "photo"
            ? historyImageThumbnail(at: history.fileURL(for: entry, kind: .files), maxPixelSize: 96) : nil
        feedback.receipt = FileDropFeedback.Receipt(photo: photo, symbol: entry.symbol)
        visibleUntil = ProcessInfo.processInfo.systemUptime + 1.1
    }
}

@MainActor
final class FileDropShelf {
    private let history: LocalHistoryStore
    private let pasteboard = NSPasteboard(name: .drag)
    private var timer: Timer?
    private var panel: NSPanel?
    private var dragChangeCount = 0
    private var shake = DragShake()
    private var tracking = false
    private var lastRelease: TimeInterval?

    init(history: LocalHistoryStore) { self.history = history }

    func start() {
        guard timer == nil else { return }
        dragChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if tracking {
                tracking = false
                lastRelease = now
                dragChangeCount = pasteboard.changeCount
            }
            let dropView = panel?.contentView as? FileDropView
            guard dropView?.isImporting != true else { return }
            let visibleUntil = dropView?.visibleUntil ?? 0
            if let lastRelease, now >= max(visibleUntil, lastRelease + 0.20) {
                panel?.orderOut(nil)
                panel = nil
                self.lastRelease = nil
            }
            return
        }

        let point = NSEvent.mouseLocation
        if !tracking {
            tracking = true
            shake = DragShake(anchor: point)
        }
        guard panel == nil, shake.sample(point, now: now) else { return }
        // Some sources only expose the drag data to the destination window.
        let dragTypesReadable = pasteboard.changeCount != dragChangeCount && pasteboard.types?.isEmpty == false
        guard !dragTypesReadable || FileDropView.canShowShelf(for: pasteboard) else { return }
        show(near: point)
    }

    private func show(near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let size = NSSize(width: 180, height: 154)
        let bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        let preferredX = point.x + 34 + size.width <= bounds.maxX ? point.x + 34 : point.x - size.width - 34
        let origin = NSPoint(x: min(max(preferredX, bounds.minX), bounds.maxX - size.width),
                             y: min(max(point.y - size.height / 2, bounds.minY), bounds.maxY - size.height))
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "우키 서랍"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = FileDropView(history: history, floating: true)
        self.panel = panel
        panel.orderFrontRegardless()
    }
}

struct DragShake {
    private var anchor: NSPoint
    private var extremum: CGFloat = 0
    private var legStarted: TimeInterval?
    private var horizontal = false
    private var direction: CGFloat = 1
    private var previousShake: TimeInterval?

    init(anchor: NSPoint = .zero) { self.anchor = anchor }

    mutating func sample(_ point: NSPoint, now: TimeInterval) -> Bool {
        if let legStarted {
            if now - legStarted > 0.65 {
                anchor = point
                self.legStarted = nil
                return false
            }
            let distance = (horizontal ? point.x - anchor.x : point.y - anchor.y) * direction
            extremum = max(extremum, distance)
            if extremum - distance >= 26 {
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
        guard abs(distance) >= 26 else { return false }
        direction = distance > 0 ? 1 : -1
        extremum = abs(distance)
        legStarted = now
        return false
    }
}
