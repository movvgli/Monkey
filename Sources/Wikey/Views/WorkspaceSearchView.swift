import AppKit
import SwiftUI
import WikeyCore

struct WorkspaceSearchView: View {
    enum Mode {
        case library(open: (SidebarSelection) -> Void)
        case launcher(close: () -> Void)
    }

    private enum Destination: Hashable {
        case library(SidebarSelection)
        case run(UUID)
        case copy(UUID)
        case copyValue(String)

        var actionTitle: String {
            switch self {
            case .library: "열기"
            case .run: "실행"
            case .copy, .copyValue: "복사"
            }
        }
    }

    private enum Utility {
        case calculation(SearchCalculation)
        case exchange(SearchCurrencyQuery)
    }

    private struct Result: Identifiable {
        var id: Destination
        var name: String
        var detail: String
        var symbol: String
        var keyword: String? = nil

        var isValue: Bool {
            if case .copyValue = id { return true }
            return false
        }
    }

    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selected: Destination?
    @State private var copyError: String?
    @State private var exchangeRates: SearchExchangeRates.Snapshot?
    @State private var exchangeLoadFailed = false
    var mode: Mode

    private var isLauncher: Bool {
        if case .launcher = mode { return true }
        return false
    }

    private func matches(for query: String) -> (entries: [Result], utility: Utility?) {
        let keywordResults = WorkflowKeyword.matches(query, in: runtime.store.workflows).map(workflowResult)
        if let utility = utility(for: query, keywordResults: keywordResults) {
            return (utilityResults(utility), utility)
        }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let entries = isLauncher ? launcherResults : libraryResults
        let keywordIDs = Set(keywordResults.map(\.id))
        let matchingEntries = entries.filter { result in
            !keywordIDs.contains(result.id) && terms.allSatisfy { term in
                result.name.localizedCaseInsensitiveContains(term) || result.detail.localizedCaseInsensitiveContains(term)
            }
        }
        return (keywordResults + matchingEntries, nil)
    }

    private func utility(for query: String, keywordResults: [Result]) -> Utility? {
        guard isLauncher else { return nil }
        if let keyword = WorkflowKeyword.normalized(query), keywordResults.first?.keyword == keyword { return nil }
        if let exchange = SearchCurrencyQuery.parse(query) { return .exchange(exchange) }
        if let calculation = SearchCalculation.evaluate(query) { return .calculation(calculation) }
        return nil
    }

    private func utilityResults(_ utility: Utility) -> [Result] {
        switch utility {
        case .calculation(.value(let value)):
            let formatted = SearchNumber.formatted(value)
            return [Result(id: .copyValue(formatted), name: formatted, detail: "계산 결과", symbol: "equal.circle")]
        case .calculation(.error):
            return []
        case .exchange(let request):
            guard let table = exchangeRates?.rates else { return [] }
            return request.targets.compactMap { target in
                guard let rate = table.rate(from: request.base, to: target) else { return nil }
                let amount = request.amount * rate
                guard !amount.isNaN else { return nil }
                let converted = "\(target.formattedAmount(amount)) \(target.rawValue)"
                let unitRate = SearchNumber.formatted(rate, maximumFractionDigits: 6)
                return Result(
                    id: .copyValue(converted), name: converted,
                    detail: "\(target.name) · 1 \(request.base.rawValue) ≈ \(unitRate) \(target.rawValue)",
                    symbol: "arrow.left.arrow.right"
                )
            }
        }
    }

    private var launcherResults: [Result] {
        let templates = runtime.store.templates.map {
            Result(id: .copy($0.id), name: $0.name, detail: "템플릿", symbol: "doc.on.clipboard")
        }
        return templates + runtime.store.workflows.filter { !$0.actions.isEmpty }.map(workflowResult)
    }

    private func workflowResult(_ workflow: Workflow) -> Result {
        let action = workflow.actions.count == 1 ? workflow.actions.first : nil
        return Result(
            id: .run(workflow.id),
            name: workflow.name,
            detail: action?.title ?? "워크플로",
            symbol: action?.wikeyIcon.symbol ?? "bolt",
            keyword: WorkflowKeyword.normalized(workflow.keyword)
        )
    }

    private var libraryResults: [Result] {
        let sections = SidebarSelection.sections.map {
            Result(id: .library($0), name: $0.title, detail: "보관함", symbol: $0.symbol)
        }
        let workflows = runtime.store.workflows.map {
            Result(id: .library(.workflow($0.id)), name: $0.name,
                   detail: $0.shortcut.steps.isEmpty ? "워크플로" : "워크플로 · \($0.shortcut.displayName)",
                   symbol: "bolt")
        }
        let apps = runtime.store.applicationShortcuts.map {
            Result(id: .library(.application($0.bundleIdentifier)), name: $0.displayName,
                   detail: "앱 · \($0.shortcut.displayName)", symbol: "app")
        }
        let templates = runtime.store.templates.map {
            Result(id: .library(.template($0.id)), name: $0.name, detail: "템플릿", symbol: "doc.on.clipboard")
        }
        let layouts = runtime.store.layouts.map {
            Result(id: .library(.layout($0.id)), name: $0.name,
                   detail: $0.shortcut.steps.isEmpty ? "레이아웃" : "레이아웃 · \($0.shortcut.displayName)",
                   symbol: "rectangle.3.group")
        }
        return sections + workflows + apps + templates + layouts
    }

    var body: some View {
        let (entries, utility) = matches(for: query)
        let actionTitle = selected?.actionTitle ?? "열기"
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                WorkspaceSearchField(
                    text: Binding(get: { query }, set: changeQuery),
                    onMove: moveSelection,
                    onSubmit: openSelected,
                    onCancel: close,
                    prompt: isLauncher ? "검색 또는 계산·환율 입력" : "템플릿·워크플로·검색 키워드 찾기"
                )
                .frame(height: 28)
                Button("닫기", wikeyIcon: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(WikeyGlossyButtonStyle(tint: .neutral, iconOnly: true))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()

            if case .exchange(let request) = utility {
                exchangeHeader(request)
            }

            if entries.isEmpty, let utility {
                utilityStatus(utility)
                    .frame(maxHeight: .infinity)
            } else if entries.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("저장한 템플릿이나 워크플로가 없습니다", systemImage: "magnifyingglass")
                        .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                }
            } else {
                resultList(entries)
            }

            Divider()
            if let copyError {
                Label(copyError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.top, 9)
            }
            HStack {
                Text("↑ ↓ 이동").foregroundStyle(.secondary)
                Text("↵ \(actionTitle)").foregroundStyle(.secondary)
                Spacer()
                Button(actionTitle, action: openSelected)
                    .buttonStyle(WikeyGlossyButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: isLauncher ? 600 : 560, height: 390)
        .onChange(of: entries.map(\.id), initial: true) { _, ids in
            if selected.map(ids.contains) != true { selected = ids.first }
        }
        .task(id: needsExchangeRates(utility)) {
            guard needsExchangeRates(utility) else { return }
            await loadExchangeRates()
        }
    }

    private func needsExchangeRates(_ utility: Utility?) -> Bool {
        if case .exchange = utility { return true }
        return false
    }

    private func loadExchangeRates() async {
        exchangeLoadFailed = false
        do {
            let snapshot = try await SearchExchangeRates.shared.latest()
            guard !Task.isCancelled else { return }
            exchangeRates = snapshot
        } catch {
            guard !Task.isCancelled else { return }
            exchangeLoadFailed = true
        }
    }

    private func exchangeHeader(_ request: SearchCurrencyQuery) -> some View {
        HStack {
            Text("\(SearchNumber.formatted(request.amount)) \(request.base.rawValue) 환산")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let exchangeRates {
                Text("\(exchangeRates.usedFallback ? "최근 확인값 · " : "")ECB 기준환율 · \(exchangeRates.rates.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
    }

    @ViewBuilder
    private func utilityStatus(_ utility: Utility) -> some View {
        switch utility {
        case .calculation(.error(let error)):
            ContentUnavailableView(error.localizedDescription, systemImage: "equal.circle")
        case .calculation(.value):
            EmptyView()
        case .exchange:
            if exchangeLoadFailed {
                ContentUnavailableView {
                    Label("환율을 불러오지 못했습니다", systemImage: "wifi.slash")
                } actions: {
                    Button("다시 시도") { Task { await loadExchangeRates() } }
                }
            } else if exchangeRates != nil {
                ContentUnavailableView("선택한 통화의 기준환율이 없습니다", systemImage: "arrow.left.arrow.right")
            } else {
                ProgressView("환율 확인 중…")
            }
        }
    }

    private func resultList(_ entries: [Result]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        Button { perform(entry.id) } label: {
                            HStack(spacing: 10) {
                                Label {
                                    Text(entry.name)
                                        .lineLimit(1)
                                } icon: {
                                    WikeyActionIcon(symbol: entry.symbol, tint: WikeyActionTint(symbol: entry.symbol), size: 17)
                                }
                                .font(entry.isValue ? .system(.title3, design: .rounded, weight: .semibold) : .body)
                                if let keyword = entry.keyword {
                                    Text(keyword)
                                        .font(.system(.caption, design: .monospaced, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.wikeyInk(in: colorScheme).opacity(0.1), in: Capsule())
                                }
                                Spacer()
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: entry.isValue ? 44 : 34)
                        }
                        .buttonStyle(WikeyHoverButtonStyle(selected: selected == entry.id))
                        .accessibilityAddTraits(selected == entry.id ? .isSelected : [])
                        .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selected) { _, id in
                if let id { scroll.scrollTo(id) }
            }
        }
    }

    private func changeQuery(_ value: String) {
        query = value
        selected = matches(for: value).entries.first?.id
        copyError = nil
    }

    private func moveSelection(_ offset: Int) {
        let ids = matches(for: query).entries.map(\.id)
        guard !ids.isEmpty else { return }
        guard let selected, let index = ids.firstIndex(of: selected) else {
            self.selected = ids.first
            return
        }
        self.selected = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func openSelected() {
        let entries = matches(for: query).entries
        guard let destination = entries.first(where: { $0.id == selected })?.id ?? entries.first?.id else { return }
        perform(destination)
    }

    private func perform(_ destination: Destination) {
        switch destination {
        case .library(let location):
            if case .library(let open) = mode { open(location) }
        case .run(let id):
            guard runtime.store.workflows.contains(where: { $0.id == id && !$0.actions.isEmpty }) else { return }
            close()
            runtime.run(workflowID: id)
        case .copy(let id):
            guard runtime.store.templates.contains(where: { $0.id == id }) else { return }
            do {
                try runtime.clipboard.copy(runtime.store.templateDocument(id: id))
                close()
            } catch {
                copyError = error.localizedDescription
            }
        case .copyValue(let value):
            do {
                try runtime.clipboard.copy(NSAttributedString(string: value))
                close()
            } catch {
                copyError = error.localizedDescription
            }
        }
    }

    private func close() {
        if case .launcher(let closePanel) = mode { closePanel() }
        else { dismiss() }
    }
}

@MainActor
final class WorkspaceSearchPanel: NSObject, NSWindowDelegate {
    private let runtime: WikeyRuntime
    private var window: SearchWindow?

    init(runtime: WikeyRuntime) {
        self.runtime = runtime
    }

    func toggle() {
        if window != nil {
            close()
            return
        }

        let panel = SearchWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 390),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Wikey 검색창"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView:
            WorkspaceSearchView(mode: .launcher(close: { [weak self] in self?.close() }))
                .environment(runtime)
                .tint(.wikeyAccent)
                .background { Color.clear.wikeyLauncherGlass().allowsHitTesting(false) }
        )
        panel.delegate = self
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: area.midX - size.width / 2,
                y: area.maxY - size.height - max(0, area.height - size.height) * 0.23
            ))
        } else {
            panel.center()
        }

        window = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? SearchWindow, panel === window else { return }
        close()
    }

    private func close() {
        guard let panel = window else { return }
        window = nil
        panel.delegate = nil
        panel.close()
    }

    private final class SearchWindow: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}


// Consume navigation commands at the field editor, where macOS handles arrows
// and Return before they reach SwiftUI. Keep the search state in the parent.
private struct WorkspaceSearchField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = AutofocusingSearchField()
        field.placeholderString = prompt
        field.setAccessibilityLabel("Wikey 검색어")
        field.controlSize = .large
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: WorkspaceSearchField

        init(parent: WorkspaceSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy command: Selector
        ) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }

    private final class AutofocusingSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                if window is NSPanel { window.initialFirstResponder = self }
                window.makeFirstResponder(self)
            }
        }
    }
}
