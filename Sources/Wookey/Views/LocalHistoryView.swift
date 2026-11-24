import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LocalHistoryView: View {
    @Environment(LocalHistoryStore.self) private var history
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var fileToDelete: LocalHistoryStore.Entry?
    @Binding var kind: HistoryKind

    private var confirmsFileDeletion: Binding<Bool> {
        Binding {
            fileToDelete != nil
        } set: { isPresented in
            if !isPresented { fileToDelete = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                WookeyFilterPicker(
                    title: "우키 폴더", selection: $kind, options: [.files, .clipboard],
                    icon: { $0 == .files ? wookeyDrawerSymbol : $0.symbol }
                ) { $0 == .files ? "서랍" : "클립보드" }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            historyList.id(kind)
        }
        .navigationTitle(HistoryKind.files.title)
        .alert("‘\(fileToDelete?.name ?? "")’을 삭제할까요?", isPresented: confirmsFileDeletion, presenting: fileToDelete) { entry in
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                history.remove(entry, kind: .files)
            }
        } message: { _ in
            Text("우키 폴더에 보관된 사본을 삭제합니다. 삭제한 항목은 되돌릴 수 없습니다.")
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
        return WookeyPageHeader(title: HistoryKind.files.title, subtitle: subtitle) {
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
                    .font(.pretendard(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("다시 복사", wookeyIcon: "doc.on.doc") { history.restoreClipboard(entry) }
            removeButton(entry) { history.remove(entry, kind: .clipboard) }
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
                    ShelfDragSource(entry: entry, file: file, history: history, icon: NSWorkspace.shared.icon(forFile: file.path))
                        .accessibilityHidden(true)
                }
                .help("클릭해서 열거나 다른 앱으로 드래그")
                HStack(spacing: 5) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.name)
                    Spacer(minLength: 0)
                    removeButton(entry) { fileToDelete = entry }
                }
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.pretendard(.caption))
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
                    .font(.pretendard(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
        } else if entry.symbol == "photo" {
            HistoryImageThumbnail(url: url)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
        }
    }

    private func removeButton(_ entry: LocalHistoryStore.Entry, action: @escaping () -> Void) -> some View {
        Button("삭제", wookeyIcon: "trash", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(WookeyGlossyButtonStyle(tint: .neutral, iconOnly: true))
            .controlSize(.small)
            .accessibilityLabel("\(entry.name) 삭제")
    }
}

struct ShelfDragSource: NSViewRepresentable {
    let entry: LocalHistoryStore.Entry
    let file: URL
    let history: LocalHistoryStore
    let icon: NSImage
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var dragEntries: (() -> [LocalHistoryStore.Entry])?

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.click = onClick ?? { _, _ in history.openFile(entry) }
        view.prepareDrag = {
            let entries = dragEntries?() ?? [entry]
            let items = entries.map { item in
                let itemFile = item.id == entry.id ? file : history.fileURL(for: item, kind: .files)
                return DragView.Item(
                    id: item.id, url: item.webURL ?? itemFile,
                    icon: item.id == entry.id ? icon : NSWorkspace.shared.icon(forFile: itemFile.path)
                )
            }
            guard !items.isEmpty, items.allSatisfy(\.isAvailable) else { return nil }
            let ids = Set(items.map(\.id))
            history.beginFileDrag(ids)
            return (items, { history.endFileDrag(ids, delivered: $0) })
        }
    }

    final class DragView: NSView, NSDraggingSource {
        struct Item {
            let id: UUID
            let url: URL
            let icon: NSImage
            @MainActor var isAvailable: Bool {
                url.isFileURL ? FileManager.default.fileExists(atPath: url.path) : LocalHistoryStore.isWebURL(url)
            }
        }

        var click: ((Int, NSEvent.ModifierFlags) -> Void)?
        var prepareDrag: (() -> ([Item], (Bool) -> Void)?)?
        private var mouseDownLocation: NSPoint?
        private var activeOperation: NSDragOperation = []
        private var finishActiveDrag: ((Bool) -> Void)?

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownLocation = nil }
            if mouseDownLocation != nil, bounds.contains(convert(event.locationInWindow, from: nil)) {
                click?(event.clickCount, event.modifierFlags)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownLocation else { return }
            let point = event.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { return }
            mouseDownLocation = nil
            guard let (items, finish) = prepareDrag?() else { return }
            let location = convert(point, from: nil)
            let draggingItems = items.enumerated().map { index, item in
                let draggingItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
                let offset = CGFloat(min(index, 4)) * 3
                draggingItem.setDraggingFrame(
                    NSRect(x: location.x - 20 + offset, y: location.y - 20 - offset, width: 40, height: 40),
                    contents: item.icon
                )
                return draggingItem
            }
            activeOperation = items.contains { $0.url.isFileURL } ? .copy : [.copy, .link]
            finishActiveDrag = finish
            let session = beginDraggingSession(with: draggingItems, event: event, source: self)
            if items.count > 1 { session.draggingFormation = .pile }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? activeOperation : []
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            finishActiveDrag?(!operation.intersection([.copy, .link]).isEmpty)
            finishActiveDrag = nil
            activeOperation = []
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
            thumbnail = await Task.detached(priority: .utility) {
                historyImageThumbnail(at: url, maxPixelSize: 360)
            }.value
        }
    }
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
    @AppStorage(WookeyCharacter.storageKey) private var selectedCharacter = WookeyCharacter.wookey
    let history: LocalHistoryStore
    let session: FloatingShelfSession
    let feedback: FileDropFeedback
    let onToggle: () -> Void
    let onClose: () -> Void
    let onMove: (NSEvent) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if session.isExpanded, session.bubbleOnLeft { thoughtBubble }
            mascotControl
                .padding(.top, session.mascotTopInset)
            if session.isExpanded, !session.bubbleOnLeft { thoughtBubble }
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
            if !session.isExpanded {
                closeButton.padding(8)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
            }
        }
    }

    private var mascot: some View {
        FileDropSurface(feedback: feedback, floating: true, isMirrored: session.isExpanded)
            .frame(width: FloatingShelfSession.mascotSize.width, height: FloatingShelfSession.mascotSize.height)
            .contentShape(Rectangle())
    }

    private var closeButton: some View {
        Button(action: onClose) {
            WookeyActionIcon(symbol: "xmark", tint: .neutral, size: 15)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .accessibilityLabel("서랍 닫기")
            .help("서랍 닫기")
            .keyboardShortcut(.cancelAction)
    }

    private var thoughtBubble: some View {
        let spacing = FloatingShelfSession.cardSpacing
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing), count: session.columnCount)
        let edge: Edge.Set = session.bubbleOnLeft ? .trailing : .leading
        let trail = ShelfThoughtTrail(
            mascotOnLeft: !session.bubbleOnLeft,
            headY: session.mascotTopInset - session.bubbleTopInset + (selectedCharacter == .sharkey ? 51 : 44)
        )
        let bodyShape = RoundedRectangle(cornerRadius: 26)
        let selectedCount = session.selection.ids.count
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                WookeyActionIcon(symbol: wookeyDrawerSymbol, tint: .amber, size: 16)
                Text(selectedCount == 0 ? "서랍" : "\(selectedCount)개 선택")
                    .font(.pretendard(.caption, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                closeButton
            }
            .padding(.horizontal, FloatingShelfSession.bubblePadding)
            .frame(height: FloatingShelfSession.headerHeight)
            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(session.entries) { entry in
                        entryCard(entry)
                    }
                }
                .padding([.horizontal, .bottom], FloatingShelfSession.bubblePadding)
                .padding(.top, 4)
            }
        }
        .clipShape(bodyShape)
        .background { thoughtBubbleBackground(bodyShape) }
        .padding(edge, FloatingShelfSession.thoughtGutterWidth)
        .background {
            trail.fill(theme.panel.opacity(reduceTransparency ? 1 : 0.76))
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, theme.colorScheme)
        .frame(width: session.bubbleWidth, height: session.bubbleHeight)
        .padding(.top, session.bubbleTopInset)
        .accessibilityLabel("서랍에 담은 항목")
    }

    private func thoughtBubbleBackground(_ shape: RoundedRectangle) -> some View {
        let isDark = theme == .dark
        return thoughtBubbleMaterial(shape)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(isDark ? 0.14 : 0.42), .clear],
                    startPoint: .topLeading, endPoint: UnitPoint(x: 0.65, y: 0.52)
                ))
            }
            .overlay {
                shape.strokeBorder(.white.opacity(isDark ? 0.20 : 0.44), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func thoughtBubbleMaterial(_ shape: RoundedRectangle) -> some View {
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
        let icon = NSWorkspace.shared.icon(forFile: file.path)
        let isSelected = session.selection.ids.contains(entry.id)
        return Button {
            session.select(entry.id)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if entry.webURL != nil {
                        WookeyActionIcon(symbol: "link", tint: .graphite, size: 30)
                    } else if entry.symbol == "photo" {
                        HistoryImageThumbnail(url: file)
                    } else {
                        Image(nsImage: icon).resizable().scaledToFit()
                    }
                }
                .frame(width: 36, height: 36)
                Text(entry.name)
                    .font(.pretendard(.caption, weight: .medium))
                    .foregroundStyle(theme == .dark ? Color(white: 0.96) : Color(white: 0.12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: FloatingShelfSession.cardHeight)
            .background(theme.canvas.opacity(reduceTransparency ? 1 : 0.75), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                let shape = RoundedRectangle(cornerRadius: 12)
                ZStack {
                    shape.fill(isSelected ? theme.selectionTint.opacity(0.15) : .clear)
                    shape.strokeBorder(isSelected ? theme.accent : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
                }
                .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(WookeyHoverButtonStyle())
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "열기") { history.openFile(entry) }
        .overlay {
            ShelfDragSource(
                entry: entry, file: file, history: history, icon: icon,
                onClick: { count, modifiers in
                    if count == 2, modifiers.intersection([.shift, .command]).isEmpty {
                        history.openFile(entry)
                    } else {
                        session.select(entry.id, modifiers: modifiers)
                    }
                },
                dragEntries: { session.entriesForDrag(from: entry) }
            )
            .accessibilityHidden(true)
        }
        .help("클릭하여 선택 · 두 번 클릭하여 열기 · 선택 항목을 드래그하여 이동")
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

private struct ShelfThoughtTrail: Shape {
    let mascotOnLeft: Bool
    let headY: CGFloat

    func path(in rect: CGRect) -> Path {
        let gutter = FloatingShelfSession.thoughtGutterWidth
        guard rect.width > gutter, rect.height >= 32 else { return Path() }
        let direction: CGFloat = mascotOnLeft ? -1 : 1
        let edge = mascotOnLeft ? rect.minX + gutter : rect.maxX - gutter
        let y = min(max(headY, rect.minY + 27), rect.maxY - 5)
        var path = Path()
        for (distance, rise, width, height): (CGFloat, CGFloat, CGFloat, CGFloat) in [(11, 15, 9, 8), (28, 4, 5, 4)] {
            path.addEllipse(in: CGRect(
                x: edge + direction * distance - width / 2,
                y: y - rise - height / 2,
                width: width, height: height
            ))
        }
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
    var isMirrored = false

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
                Text("파일을 끌다가 두 번 흔들면 우키 서랍이 열려요.")
                    .font(.pretendard(.subheadline))
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
        .scaleEffect(x: isMirrored ? -1 : 1, y: 1, anchor: .center)
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
        .font(.pretendard(size: 15, weight: .semibold))
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
                                    .font(.pretendard(.caption))
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
                    .font(.pretendard(.headline))
                    .accessibilityAddTraits(.isHeader)
                Text(description(for: kind))
                    .font(.pretendard(.subheadline))
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
                            .font(.pretendard(.caption))
                            .foregroundStyle(.secondary)
                    } else if let seconds = proposedRetention?.seconds,
                              seconds < (saved.seconds ?? .infinity) {
                        Text("새 보관 기간이 지난 기록은 적용 즉시 삭제됩니다.")
                            .font(.pretendard(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("적용", wookeyIcon: "checkmark.circle.fill") {
                        if let proposedRetention {
                            history.setRetention(proposedRetention, for: kind)
                        }
                    }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .disabled(proposedRetention == nil)
                }
            }
        }
        .onChange(of: saved, initial: true) { _, value in
            draft = value
            amount = String(value.amount)
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
