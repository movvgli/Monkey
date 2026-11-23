import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LocalHistoryView: View {
    @Environment(LocalHistoryStore.self) private var history
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var kind: HistoryKind
    @State private var pendingRemoval: LocalHistoryStore.Entry?

    init(initialKind: HistoryKind = .files) {
        _kind = State(initialValue: initialKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                WookeyFilterPicker(
                    title: "파일 보관함", selection: $kind, options: [.files, .clipboard], icon: { $0.symbol }
                ) { $0 == .files ? "서랍" : "클립보드" }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            historyList.id(kind)
        }
        .navigationTitle("파일")
        .confirmationDialog(
            "이 항목을 삭제할까요?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { entry in
            Button("삭제", role: .destructive) { history.remove(entry, kind: kind) }
            Button("취소", role: .cancel) {}
        } message: { entry in
            Text("‘\(entry.name)’ 항목과 보관된 내용이 함께 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                isImporting = true
                Task {
                    var failed = false
                    for url in urls {
                        if await history.importFile(at: url) == nil { failed = true }
                    }
                    if failed { history.showFileImportError() }
                    isImporting = false
                }
            case .failure:
                history.showFileImportError()
            }
        }
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WookeyPageMetrics.headerSpacing) {
                if kind == .files {
                    FileDropTarget(history: history)
                        .frame(height: 146)
                }
                if let error = history.errors[kind] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                let entries = history.entries(kind)
                if entries.isEmpty {
                    ContentUnavailableView {
                        WookeyEmptyStateLabel(
                            title: kind == .clipboard ? "클립보드 기록이 없습니다" : "보관한 파일이나 링크가 없습니다",
                            symbol: kind.symbol
                        )
                    } description: {
                        Text(emptyDescription)
                    }
                    .frame(maxWidth: .infinity, minHeight: 175)
                } else if kind == .clipboard {
                    PlainPanel {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                if entry.id != entries.first?.id { Divider() }
                                clipboardRow(entry)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(entries) { entry in
                            fileCard(entry)
                        }
                    }
                }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var emptyDescription: String {
        if kind == .files { return "파일이나 링크를 위에 놓거나 ‘파일 추가’를 사용하세요." }
        return history.recordsClipboard
            ? "텍스트, 이미지 또는 파일을 복사하면 여기에 표시됩니다."
            : "설정의 보관 기간 탭에서 클립보드 기록을 켤 수 있습니다."
    }

    private var header: some View {
        let subtitle = kind == .clipboard
            ? "최근 복사한 내용을 찾아 다시 복사합니다."
            : "우키 서랍에 담은 파일과 웹 링크를 열 수 있습니다."
        return WookeyPageHeader(title: "파일", subtitle: subtitle) {
            if kind == .files {
                Button(isImporting ? "가져오는 중…" : "파일 추가", wookeyIcon: "plus") { showsImporter = true }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
                    .disabled(isImporting)
            }
        }
    }

    private func clipboardRow(_ entry: LocalHistoryStore.Entry) -> some View {
        HStack(spacing: 10) {
            WookeyActionIcon(symbol: entry.symbol, tint: WookeyActionTint(symbol: entry.symbol), size: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).lineLimit(2)
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("다시 복사", wookeyIcon: "doc.on.doc") { history.restoreClipboard(entry) }
            removeButton(entry)
        }
        .padding(.vertical, 8)
    }

    private func fileCard(_ entry: LocalHistoryStore.Entry) -> some View {
        PlainPanel {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    history.openFile(entry)
                } label: {
                    filePreview(entry)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.name) 열기")
                .overlay {
                    let file = history.fileURL(for: entry, kind: .files)
                    ShelfDragSource(entry: entry, file: file, history: history, icon: WookeyIconCache.icon(forFile: file.path))
                    .accessibilityHidden(true)
                }
                .help("클릭해서 열거나 다른 앱으로 드래그")
                HStack(spacing: 5) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.name)
                    Spacer(minLength: 0)
                    removeButton(entry)
                }
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func filePreview(_ entry: LocalHistoryStore.Entry) -> some View {
        let url = history.fileURL(for: entry, kind: .files)
        if let webURL = entry.webURL {
            VStack(spacing: 5) {
                WookeyActionIcon(symbol: "link", tint: .graphite, size: 42)
                Text(webURL.host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
        } else if entry.symbol == "photo" {
            HistoryImageThumbnail(url: url)
        } else {
            WookeyFileIcon(path: url.path)
                .frame(width: 52, height: 52)
        }
    }

    private func removeButton(_ entry: LocalHistoryStore.Entry) -> some View {
        Button("삭제", wookeyIcon: "trash") { pendingRemoval = entry }
            .labelStyle(.iconOnly)
            .buttonStyle(WookeyGlossyButtonStyle(tint: .neutral, iconOnly: true))
            .controlSize(.small)
            .accessibilityLabel("\(entry.name) 삭제")
            .help("삭제")
    }
}

struct ShelfDragSource: NSViewRepresentable {
    let entry: LocalHistoryStore.Entry
    let file: URL
    let history: LocalHistoryStore
    let icon: NSImage

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.url = entry.webURL ?? file
        view.icon = icon
        view.open = { history.openFile(entry) }
        view.startDrag = { history.beginFileDrag(entry.id) }
        view.endDrag = { history.endFileDrag(entry.id, delivered: $0) }
    }

    final class DragView: NSView, NSDraggingSource {
        var url: URL?
        var icon: NSImage?
        var open: (() -> Void)?
        var startDrag: (() -> Void)?
        var endDrag: ((Bool) -> Void)?
        private var mouseDownLocation: NSPoint?
        private var finishActiveDrag: ((Bool) -> Void)?

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownLocation = nil }
            if mouseDownLocation != nil, bounds.contains(convert(event.locationInWindow, from: nil)) {
                open?()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownLocation, let url, let icon else { return }
            let point = event.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
            mouseDownLocation = nil
            guard url.isFileURL ? FileManager.default.fileExists(atPath: url.path) : LocalHistoryStore.isWebURL(url) else { return }

            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let location = convert(point, from: nil)
            item.setDraggingFrame(NSRect(x: location.x - 20, y: location.y - 20, width: 40, height: 40), contents: icon)
            finishActiveDrag = endDrag
            startDrag?()
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            guard context == .outsideApplication else { return [] }
            return url?.isFileURL == true ? .copy : [.copy, .link]
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            finishActiveDrag?(!operation.intersection([.copy, .link]).isEmpty)
            finishActiveDrag = nil
        }
    }
}

private struct HistoryImageThumbnail: View {
    let url: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                WookeyActionIcon(symbol: "photo", tint: .neutral, size: 20)
            }
        }
        .task(id: url) {
            if let cached = HistoryThumbnailCache.shared.image(for: url) {
                thumbnail = cached
                return
            }
            // Cells that only fly past during a fast scroll never start decoding.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            // Forward cancellation (e.g. the cell scrolled away) to the background decode.
            // A decode ImageIO already started cannot be interrupted, so its result is
            // cached and reused when the cell comes back instead of being thrown away.
            let decode = Task.detached(priority: .utility) { () -> CGImage? in
                guard !Task.isCancelled,
                      let image = historyImageThumbnail(at: url, maxPixelSize: 360) else { return nil }
                HistoryThumbnailCache.shared.store(image, for: url)
                return image
            }
            let image = await withTaskCancellationHandler {
                await decode.value
            } onCancel: {
                decode.cancel()
            }
            if !Task.isCancelled { thumbnail = image }
        }
    }
}

/// Thread-safe (NSCache) store of decoded history thumbnails, bounded by count.
private final class HistoryThumbnailCache: @unchecked Sendable {
    static let shared = HistoryThumbnailCache()
    private let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.countLimit = 300
        return cache
    }()

    func image(for url: URL) -> CGImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: CGImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

func historyImageThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct FloatingShelfView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let history: LocalHistoryStore
    let session: FloatingShelfSession
    let feedback: FileDropFeedback
    let onToggle: () -> Void
    let onClose: () -> Void
    let onMove: (NSEvent) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if session.isExpanded, session.bubbleOnLeft { speechBubble }
            mascotControl
                .padding(.top, session.mascotTopInset)
            if session.isExpanded, !session.bubbleOnLeft { speechBubble }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover { isHovered = $0 }
    }

    private var mascotControl: some View {
        Group {
            if session.entries.isEmpty {
                mascot
                    .accessibilityLabel(feedback.isReceiving ? "가져오는 중" : "파일이나 링크를 놓으세요")
            } else {
                Button(action: onToggle) { mascot }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.isExpanded ? "서랍 목록 접기" : "서랍 목록 열기")
                    .accessibilityValue("\(session.entries.count)개 항목")
            }
        }
        .overlay {
            ShelfMascotInteraction(onClick: session.entries.isEmpty ? nil : onToggle, onMove: onMove)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            Button("서랍 닫기", wookeyIcon: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                .controlSize(.small)
                .accessibilityLabel("서랍 닫기")
                .help("서랍 닫기")
                .padding(8)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .keyboardShortcut(.cancelAction)
        }
    }

    private var mascot: some View {
        FileDropSurface(feedback: feedback, floating: true)
            .frame(width: FloatingShelfSession.mascotSize.width, height: FloatingShelfSession.mascotSize.height)
            .contentShape(Rectangle())
    }

    private var speechBubble: some View {
        let spacing = FloatingShelfSession.cardSpacing
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: session.columnCount)
        let edge: Edge.Set = session.bubbleOnLeft ? .trailing : .leading
        let shape = ShelfThoughtBubble(
            mascotOnLeft: !session.bubbleOnLeft,
            dotOriginY: session.mascotTopInset + FloatingShelfSession.mascotSize.height / 3
        )
        return ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(session.entries) { entry in
                    entryCard(entry)
                }
            }
            .padding(FloatingShelfSession.bubblePadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(edge, FloatingShelfSession.thoughtGutterWidth)
        .background { thoughtBubbleBackground(shape) }
        .environment(\.colorScheme, theme.colorScheme)
        .frame(width: session.bubbleWidth)
        .accessibilityLabel("서랍에 담은 항목")
    }

    private func thoughtBubbleBackground(_ shape: ShelfThoughtBubble) -> some View {
        let isDark = theme == .dark
        return thoughtBubbleMaterial(shape)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(isDark ? 0.14 : 0.42), .clear],
                    startPoint: .topLeading, endPoint: UnitPoint(x: 0.65, y: 0.52)
                ))
            }
            .overlay {
                shape.stroke(.white.opacity(isDark ? 0.25 : 0.60), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func thoughtBubbleMaterial(_ shape: ShelfThoughtBubble) -> some View {
        let fallback = reduceTransparency ? AnyShapeStyle(theme.panel) : AnyShapeStyle(.thinMaterial)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            Color.clear
                .glassEffect(.clear, in: shape)
                .clipShape(shape)
        } else {
            shape.fill(fallback)
        }
        #else
        shape.fill(fallback)
        #endif
    }

    private func entryCard(_ entry: LocalHistoryStore.Entry) -> some View {
        let file = history.fileURL(for: entry, kind: .files)
        return Button {
            history.openFile(entry)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if entry.webURL != nil {
                        WookeyActionIcon(symbol: "link", tint: .graphite, size: 30)
                    } else if entry.symbol == "photo" {
                        HistoryImageThumbnail(url: file)
                    } else {
                        WookeyFileIcon(path: file.path)
                    }
                }
                .frame(width: 36, height: 36)
                Text(entry.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme == .dark ? Color(white: 0.96) : Color(white: 0.12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: FloatingShelfSession.cardHeight)
            .background(theme.canvas.opacity(reduceTransparency ? 1 : 0.66), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.09))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(WookeyHoverButtonStyle())
        .accessibilityLabel("\(entry.name) 열기")
        .overlay {
            ShelfDragSource(entry: entry, file: file, history: history, icon: WookeyIconCache.icon(forFile: file.path))
                .accessibilityHidden(true)
        }
        .help("클릭해서 열거나 다른 앱으로 드래그")
    }
}

private struct ShelfMascotInteraction: NSViewRepresentable {
    let onClick: (() -> Void)?
    let onMove: (NSEvent) -> Void

    func makeNSView(context: Context) -> MascotView { MascotView() }

    func updateNSView(_ view: MascotView, context: Context) {
        view.onClick = onClick
        view.onMove = onMove
    }

    final class MascotView: NSView {
        var onClick: (() -> Void)?
        var onMove: ((NSEvent) -> Void)?
        private var mouseDownEvent: NSEvent?
        private var isMoving = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            isMoving = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent else { return }
            if !isMoving {
                guard let start = mouseDownEvent.cgEvent?.location,
                      let location = event.cgEvent?.location,
                      hypot(location.x - start.x, location.y - start.y) >= 4 else { return }
                isMoving = true
                onMove?(mouseDownEvent)
            }
            onMove?(event)
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                isMoving = false
            }
            if isMoving {
                onMove?(event)
            } else if mouseDownEvent != nil, bounds.contains(convert(event.locationInWindow, from: nil)) {
                onClick?()
            }
        }
    }
}

private struct ShelfThoughtBubble: Shape {
    let mascotOnLeft: Bool
    let dotOriginY: CGFloat

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 0.5, dy: 0.5)
        let width = FloatingShelfSession.thoughtGutterWidth
        guard bounds.width > width, bounds.height > 1 else { return Path() }
        let body = CGRect(
            x: bounds.minX + (mascotOnLeft ? width : 0), y: bounds.minY,
            width: bounds.width - width, height: bounds.height
        )
        let direction: CGFloat = mascotOnLeft ? -1 : 1
        let edge = mascotOnLeft ? body.minX : body.maxX
        let y = min(max(dotOriginY, bounds.minY + 10), bounds.maxY - 10)
        var path = Path(roundedRect: body, cornerRadius: 22)
        path.addEllipse(in: CGRect(x: edge + direction * 8 - 4, y: y - 9, width: 8, height: 8))
        path.addEllipse(in: CGRect(x: edge + direction * 18 - 2.5, y: y + 1, width: 5, height: 5))
        return path
    }
}

struct FileDropSurface: View {
    @AppStorage(WookeyCharacter.storageKey) private var selectedCharacter = WookeyCharacter.wookey
    @AppStorage(WookeyIconTheme.storageKey) private var iconTheme = WookeyIconTheme.threeDimensional
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var biteStage: BiteStage = .idle
    let feedback: FileDropFeedback
    let floating: Bool

    private enum BiteStage { case idle, offered, swallowed, saved }

    private var characterSize: CGFloat { floating ? 118 : 100 }
    private var mouthOffset: CGSize {
        switch selectedCharacter {
        case .wookey where iconTheme == .fluffy:
            CGSize(width: characterSize * -0.05, height: characterSize * -0.07)
        case .wookey: CGSize(width: characterSize * -0.054, height: characterSize * -0.078)
        case .sharkey: CGSize(width: characterSize * -0.28, height: characterSize * 0.048)
        }
    }

    private var mouthIsOpen: Bool { feedback.isTargeted || biteStage == .offered }
    private var isSaved: Bool { biteStage == .saved }

    var body: some View {
        VStack(spacing: 4) {
            character
            if !floating {
                message
                Text("파일이나 링크를 끌다가 두 번 흔들면 우키 서랍이 열려요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !floating { WookeyGlossyPanel(radius: 18) }
        }
        .overlay {
            if !floating {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(feedback.isTargeted ? theme.selectionTint : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: feedback.isTargeted)
        .task(id: feedback.receipt?.id) {
            guard feedback.receipt != nil else { return }
            await playBite()
        }
    }

    private var character: some View {
        ZStack {
            if !floating || feedback.isTargeted {
                Circle()
                    .fill(theme.selectionTint.opacity(feedback.isTargeted ? 0.5 : 0.22))
                    .frame(width: 72, height: 72)
                    .blur(radius: 6)
            }
            ZStack {
                Image(iconTheme.asset(selectedCharacter.shelfArtwork, fallback: WookeyCharacter.wookey.shelfArtwork),
                      bundle: wookeyAssetBundle)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                Ellipse()
                    .fill(WookeyTheme.cocoa)
                    .frame(width: selectedCharacter == .sharkey ? 9 : 8, height: 7)
                    .rotationEffect(.degrees(14))
                    .offset(mouthOffset)
                    .opacity(mouthIsOpen ? 1 : 0)
            }
            .frame(width: characterSize, height: characterSize)
            .scaleEffect(reduceMotion ? 1 : characterScale)

            if !reduceMotion, let receipt = feedback.receipt {
                receiptCard(receipt)
                    .rotationEffect(.degrees(biteStage == .offered ? -14 : 0))
                    .scaleEffect(biteStage == .offered ? 1 : 0.13)
                    .offset(biteStage == .offered ? CGSize(width: -46, height: 12) : mouthOffset)
                    .opacity(biteStage == .offered ? 1 : 0)
            }
        }
        .frame(width: 124, height: 90)
        .accessibilityHidden(true)
    }

    private var characterScale: CGFloat {
        if biteStage == .swallowed { return 0.91 }
        if mouthIsOpen || isSaved { return 1.06 }
        return 1
    }

    private var message: some View {
        let title = if isSaved { "서랍에 담았어요" }
        else if feedback.isReceiving { "가져오는 중…" }
        else if feedback.isTargeted { "여기에 놓으세요" }
        else { "파일이나 링크를 놓으세요" }
        return HStack(spacing: 5) {
            if isSaved { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
            Text(title)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(theme.accent)
        .lineLimit(1)
    }

    private func receiptCard(_ receipt: FileDropFeedback.Receipt) -> some View {
        Group {
            if let photo = receipt.photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                WookeyActionIcon(symbol: receipt.symbol, tint: WookeyActionTint(symbol: receipt.symbol), size: 20)
            }
        }
        .frame(width: 28, height: 24)
        .background(theme.canvas)
        .clipShape(.rect(cornerRadius: 3))
        .padding(3)
        .background(.white, in: .rect(cornerRadius: 5))
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    @MainActor
    private func playBite() async {
        do {
            if !reduceMotion {
                biteStage = .offered
                try await Task.sleep(for: .milliseconds(85))
                withAnimation(.easeIn(duration: 0.22)) { biteStage = .swallowed }
                try await Task.sleep(for: .milliseconds(230))
            }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.35)) { biteStage = .saved }
            try await Task.sleep(for: .milliseconds(625))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { biteStage = .idle }
        } catch {
            // A more recent drop restarts the animation.
        }
    }
}

struct HistorySettingsView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(LocalHistoryStore.self) private var history

    var body: some View {
        WookeySection(
            title: "보관 기간",
            detail: "기록은 이 Mac에만 저장되며, 보관 기간이 지나면 자동으로 삭제됩니다."
        ) {
            ForEach(HistoryKind.allCases, id: \.self) { kind in
                PlainPanel {
                    HStack(alignment: .top, spacing: 12) {
                        WookeyActionIcon(symbol: kind.symbol, tint: WookeyActionTint(symbol: kind.symbol), size: 26)
                        VStack(alignment: .leading, spacing: 12) {
                            historyHeader(for: kind)
                            Divider()
                            HistoryRetentionControls(kind: kind)
                            if let error = history.errors[kind] {
                                WookeyControlLabel(title: error, symbol: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyHeader(for kind: HistoryKind) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(description(for: kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if kind == .clipboard {
                Toggle("클립보드 기록", isOn: Binding(
                    get: { history.recordsClipboard },
                    set: { history.setRecordsClipboard($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(theme.selectionTint)
            }
        }
    }

    private func description(for kind: HistoryKind) -> String {
        switch kind {
        case .clipboard:
            history.recordsClipboard
                ? "복사한 텍스트, 이미지, 파일을 기록합니다."
                : "새로 복사한 내용은 기록하지 않습니다."
        case .files:
            "우키 서랍에 추가한 파일과 웹 링크를 저장합니다."
        }
    }
}

private struct HistoryRetentionControls: View {
    @Environment(LocalHistoryStore.self) private var history
    @State private var draft = HistoryRetention()
    @State private var amount = ""
    @State private var showsShorteningConfirmation = false
    let kind: HistoryKind

    var body: some View {
        let saved = history.retention(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("보관 기간")
                Spacer()
                Picker("\(kind.title) 보관 기간", selection: $draft.period) {
                    ForEach(HistoryRetention.Period.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            if draft.period == .custom {
                HStack {
                    Text("직접 설정한 기간")
                    Spacer()
                    TextField("기간", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(kind.title) 보관 기간 값")
                    Picker("기간 단위", selection: $draft.unit) {
                        ForEach(HistoryRetention.Unit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if hasChanges(from: saved) {
                HStack(spacing: 12) {
                    if proposedRetention == nil {
                        Text("1 이상의 정수를 입력하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let seconds = proposedRetention?.seconds,
                              seconds < (saved.seconds ?? .infinity) {
                        Text("새 보관 기간이 지난 기록은 적용 즉시 삭제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("적용", wookeyIcon: "checkmark.circle.fill") {
                        if let seconds = proposedRetention?.seconds, seconds < (saved.seconds ?? .infinity) {
                            showsShorteningConfirmation = true
                        } else {
                            applyRetention()
                        }
                    }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .disabled(proposedRetention == nil)
                    .confirmationDialog(
                        "보관 기간을 줄일까요?",
                        isPresented: $showsShorteningConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("적용", role: .destructive, action: applyRetention)
                        Button("취소", role: .cancel) {}
                    } message: {
                        Text("새 보관 기간이 지난 \(kind.title) 기록이 즉시 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
                    }
                }
            }
        }
        .onChange(of: saved, initial: true) { _, value in
            draft = value
            amount = String(value.amount)
        }
    }

    private func applyRetention() {
        if let proposedRetention {
            history.setRetention(proposedRetention, for: kind)
        }
    }

    private var proposedRetention: HistoryRetention? {
        guard draft.period == .custom else { return draft }
        guard let amount = Int(amount.trimmingCharacters(in: .whitespaces)), amount > 0 else { return nil }
        var proposed = draft
        proposed.amount = amount
        return proposed
    }

    private func hasChanges(from saved: HistoryRetention) -> Bool {
        draft.period == .custom ? proposedRetention != saved : draft.period != saved.period
    }
}
