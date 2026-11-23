import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct ImageDropTarget: NSViewRepresentable {
    let history: LocalHistoryStore

    func makeNSView(context: Context) -> ImageDropView { ImageDropView(history: history) }
    func updateNSView(_ nsView: ImageDropView, context: Context) {}
}

@MainActor
@Observable
final class ImageDropFeedback {
    struct Receipt {
        let id = UUID()
        let photo: CGImage?
    }

    var isTargeted = false
    var isReceiving = false
    var receipt: Receipt?
}

@MainActor
final class ImageDropView: NSView {
    private let history: LocalHistoryStore
    private let feedback = ImageDropFeedback()
    private(set) var visibleUntil: TimeInterval = 0
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init(UTType.jpeg.identifier)]
    private static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(history: LocalHistoryStore, floating: Bool = false) {
        self.history = history
        super.init(frame: .zero)
        let artwork = NSHostingView(rootView:
            ImageDropSurface(feedback: feedback, floating: floating)
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
        setAccessibilityLabel("우키에게 이미지를 놓는 드롭 영역")
        registerForDraggedTypes([.fileURL] + Self.imageTypes + Self.promiseTypes)
    }

    required init?(coder: NSCoder) { nil }

    static func accepts(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: imageTypes + promiseTypes) != nil { return true }
        return fileURLs(on: pasteboard).contains {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
                || (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let acceptsDrop = sender.draggingSourceOperationMask.contains(.copy) && Self.accepts(sender.draggingPasteboard)
        feedback.isTargeted = acceptsDrop
        return acceptsDrop ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { feedback.isTargeted = false }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        feedback.isTargeted = false
        let pasteboard = sender.draggingPasteboard
        let images = Self.fileURLs(on: pasteboard)
        if !images.isEmpty {
            let imported = images.map { history.importImage(at: $0) }.contains(true)
            if imported {
                showReceipt()
                return true
            }
        }
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self])?
            .compactMap { $0 as? NSFilePromiseReceiver } ?? []
        if !promises.isEmpty {
            return receive(promises)
        }
        for type in Self.imageTypes {
            guard let data = pasteboard.data(forType: type), let imageType = UTType(type.rawValue) else { continue }
            if history.importImage(data: data, type: imageType) {
                showReceipt()
                return true
            }
        }
        history.showImageImportError()
        return false
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?
            .compactMap { $0 as? URL } ?? []
    }

    private func receive(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            history.showImageImportError()
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
                    self?.feedback.isReceiving = false
                    if error == nil, history.importImage(at: url) {
                        self?.showReceipt()
                    } else {
                        history.showImageImportError()
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
            history.showImageImportError()
        }
        return receiving
    }

    private func showReceipt() {
        let photo = history.entries(.images).first.flatMap { entry in
            historyImageThumbnail(at: history.fileURL(for: entry, kind: .images), maxPixelSize: 96)
        }
        feedback.receipt = ImageDropFeedback.Receipt(photo: photo)
        visibleUntil = ProcessInfo.processInfo.systemUptime + 1.1
    }
}

@MainActor
final class ImageDropShelf {
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
            let visibleUntil = (panel?.contentView as? ImageDropView)?.visibleUntil ?? 0
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
        guard !dragTypesReadable || ImageDropView.accepts(pasteboard) else { return }
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
        panel.title = "이미지 드롭박스"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = ImageDropView(history: history, floating: true)
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
