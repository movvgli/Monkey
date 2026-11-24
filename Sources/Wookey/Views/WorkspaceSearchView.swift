import AppKit
import SwiftUI
import WookeyCore

struct WorkspaceSearchView: View {
    @Environment(\.wookeyTheme) private var theme
    enum Mode {
        case library(open: (SidebarSelection) -> Void)
        case launcher(close: () -> Void)
    }

    private enum Destination: Hashable {
        case library(SidebarSelection)
        case run(UUID)
        case copy(UUID)
        case pasteTemplate(UUID)
        case copyValue(String)
        case history(HistoryKind)
        case historyEntry(HistoryKind, UUID)
        case openApplication(InstalledApplication)
        case openWebAddress(URL)

        var actionTitle: String {
            switch self {
            case .library, .openApplication: "열기"
            case .openWebAddress: "브라우저에서 열기"
            case .run: "실행"
            case .pasteTemplate: "붙여넣기"
            case .copy, .copyValue: "복사"
            case .history: "보기"
            case .historyEntry(let kind, _): kind == .clipboard ? "다시 복사" : "열기"
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
        var searchAliases: [String] = []

        var isValue: Bool {
            if case .copyValue = id { return true }
            return false
        }
    }

    @Environment(WookeyRuntime.self) private var runtime
    @Environment(LocalHistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selected: Destination?
    @State private var actionError: String?
    @State private var historyKind: HistoryKind?
    @State private var previousQuery = ""
    @State private var installedApplications: [InstalledApplication] = []
    @State private var exchangeRates: SearchExchangeRates.Snapshot?
    @State private var exchangeLoadFailed = false
    var mode: Mode

    private var isLauncher: Bool {
        if case .launcher = mode { return true }
        return false
    }

    private func matches(for query: String) -> (entries: [Result], utility: Utility?) {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if let historyKind {
            let entries = history.entries(historyKind).sorted { $0.date > $1.date }.compactMap { entry -> Result? in
                guard terms.allSatisfy({ entry.name.localizedCaseInsensitiveContains($0) }) else { return nil }
                return Result(
                    id: .historyEntry(historyKind, entry.id), name: entry.name,
                    detail: entry.date.formatted(date: .abbreviated, time: .shortened), symbol: entry.symbol
                )
            }
            return (entries, nil)
        }
        let webAddress = SearchWebAddress.parse(query)
        let keywordResults = WorkflowKeyword.matches(query, in: runtime.store.workflows, templates: runtime.store.templates).map {
            switch $0.target {
            case .workflow(let workflow): workflowResult(workflow, matchingKeyword: $0.keyword)
            case .template(let template): templateResult(template, matchingKeyword: $0.keyword)
            }
        }
        if webAddress == nil, let utility = utility(for: query, keywordResults: keywordResults) {
            return (utilityResults(utility), utility)
        }
        let entries = isLauncher ? launcherResults : libraryResults
        let keywordIDs = Set(keywordResults.map(\.id))
        let matchingEntries = entries.filter { result in
            !keywordIDs.contains(result.id) && terms.allSatisfy { term in
                [result.name, result.detail].contains { $0.localizedCaseInsensitiveContains(term) }
                    || result.searchAliases.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
        let applications = isLauncher && !terms.isEmpty ? applicationResults(matching: terms) : []
        let webResults = webAddress.map {
            [Result(id: .openWebAddress($0), name: $0.absoluteString, detail: "웹사이트", symbol: "link")]
        } ?? []
        return (webResults + keywordResults + matchingEntries + applications, nil)
    }

    private func applicationResults(matching terms: [String]) -> [Result] {
        installedApplications.compactMap { application in
            guard application.matchesSearchTerms(terms) else { return nil }
            return Result(id: .openApplication(application), name: application.displayName, detail: "설치된 앱", symbol: "app")
        }
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
        let historyActions = [
            Result(
                id: .history(.clipboard), name: "클립보드 열기", detail: "Wookey",
                symbol: HistoryKind.clipboard.symbol, searchAliases: ["복사 기록", "open clipboard"]
            ),
            Result(
                id: .history(.files), name: "우키 폴더 열기", detail: "Wookey",
                symbol: HistoryKind.files.symbol, searchAliases: ["파일함 열기", "파일 보관함", "서랍", "open files", "open folder", "drawer"]
            )
        ]
        let templates = runtime.store.templates.map { templateResult($0) }
        return historyActions + templates + runtime.store.workflows.filter { !$0.actions.isEmpty }.map { workflowResult($0) }
    }

    private func templateResult(_ template: RichTemplate, matchingKeyword: String? = nil) -> Result {
        let destination: Destination = if !isLauncher { .library(.template(template.id)) }
        else if template.deliveryMode == .copyAndPaste { .pasteTemplate(template.id) }
        else { .copy(template.id) }
        return Result(
            id: destination, name: template.name, detail: "템플릿", symbol: wookeyTemplateSymbol,
            keyword: matchingKeyword ?? WorkflowKeyword.normalized(template.keywords?.first)
        )
    }

    private func workflowResult(_ workflow: Workflow, matchingKeyword: String? = nil) -> Result {
        let action = workflow.actions.count == 1 ? workflow.actions.first : nil
        return Result(
            id: .run(workflow.id),
            name: workflow.name,
            detail: action?.title ?? "워크플로",
            symbol: action?.wookeyIcon.symbol ?? "bolt",
            keyword: matchingKeyword ?? WorkflowKeyword.normalized(workflow.keywords.first)
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
        let templates = runtime.store.templates.map { templateResult($0) }
        let layouts = runtime.store.layouts.map {
            Result(id: .library(.layout($0.id)), name: $0.name,
                   detail: $0.shortcut.steps.isEmpty ? "레이아웃" : "레이아웃 · \($0.shortcut.displayName)",
                   symbol: "rectangle.3.group")
        }
        let clipboard = Result(id: .library(.clipboard), name: "클립보드", detail: "우키 폴더", symbol: HistoryKind.clipboard.symbol)
        return sections + [clipboard] + workflows + apps + templates + layouts
    }

    var body: some View {
        let (entries, utility) = matches(for: query)
        let actionTitle = selected?.actionTitle ?? "열기"
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if historyKind != nil {
                    Button("뒤로", wookeyIcon: "chevron.left", action: backOrClose)
                        .labelStyle(.iconOnly)
                        .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                        .keyboardShortcut(.cancelAction)
                }
                WorkspaceSearchField(
                    text: Binding(get: { query }, set: changeQuery),
                    onMove: moveSelection,
                    onSubmit: openSelected,
                    onWebSearch: searchWeb,
                    onCancel: backOrClose,
                    prompt: historyPrompt ?? (isLauncher ? "앱·워크플로 검색, 웹 주소 입력, 계산·환율" : "보관함 검색 또는 웹 주소 입력")
                )
                .frame(height: 28)
                Button("닫기", wookeyIcon: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                    .keyboardShortcut(historyKind == nil ? .cancelAction : nil)
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
                    ContentUnavailableView(historyEmptyTitle ?? (isLauncher ? "앱 이름을 입력해 검색하세요" : "저장한 템플릿이나 워크플로가 없습니다"),
                                           systemImage: "magnifyingglass")
                        .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                }
            } else {
                resultList(entries)
            }

            Divider()
            if let actionError {
                Label(actionError, systemImage: "exclamationmark.triangle")
                    .font(.pretendard(.caption))
                    .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.top, 9)
            }
            HStack {
                if selected != nil {
                    Text("↑ ↓ 이동").foregroundStyle(.secondary)
                    Text("↵ \(actionTitle)").foregroundStyle(.secondary)
                }
                Spacer()
                if historyKind == nil {
                    Button("웹 검색  ⌘↵", action: searchWeb)
                        .buttonStyle(WookeyGlossyButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("웹 검색")
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button(actionTitle, action: openSelected)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            .font(.pretendard(.caption))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: isLauncher ? 600 : 560, height: 390)
        .background {
            if isLauncher { Color.clear.wookeyLauncherGlass(theme: theme).allowsHitTesting(false) }
        }
        .onChange(of: entries.map(\.id), initial: true) { _, ids in
            if selected.map(ids.contains) != true { selected = ids.first }
        }
        .task {
            guard isLauncher else { return }
            let applications = await InstalledApplicationCatalog.load()
            guard !Task.isCancelled else { return }
            installedApplications = applications
        }
        .task(id: needsExchangeRates(utility)) {
            guard needsExchangeRates(utility) else { return }
            await loadExchangeRates()
        }
    }

    private var historyPrompt: String? {
        historyKind.map { $0 == .clipboard ? "최근 클립보드 검색" : "우키 폴더 검색" }
    }

    private var historyEmptyTitle: String? {
        historyKind.map { $0 == .clipboard ? "클립보드 기록이 없습니다" : "우키 폴더에 항목이 없습니다" }
    }

    private func backOrClose() {
        guard historyKind != nil else {
            close()
            return
        }
        historyKind = nil
        changeQuery(previousQuery)
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
                .font(.pretendard(.subheadline, weight: .semibold))
            Spacer()
            if let exchangeRates {
                Text("\(exchangeRates.usedFallback ? "최근 확인값 · " : "")ECB 기준환율 · \(exchangeRates.rates.date)")
                    .font(.pretendard(.caption))
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
                                    if case .openApplication(let application) = entry.id {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.path))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 17, height: 17)
                                    } else {
                                        WookeyActionIcon(symbol: entry.symbol, tint: WookeyActionTint(symbol: entry.symbol), size: 17)
                                    }
                                }
                                .font(entry.isValue ? .pretendard(.title3, weight: .semibold) : .pretendard(.body))
                                if let keyword = entry.keyword {
                                    Text(keyword)
                                        .font(.pretendard(.caption, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.wookeyInk(in: colorScheme).opacity(0.1), in: Capsule())
                                }
                                Spacer()
                                Text(entry.detail)
                                    .font(.pretendard(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: entry.isValue ? 44 : 34)
                        }
                        .buttonStyle(WookeyHoverButtonStyle(selected: selected == entry.id))
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
        actionError = nil
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

    private func searchWeb() {
        guard historyKind == nil, (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true,
              let url = SearchWebAddress.searchURL(for: query) else { return }
        openInBrowser(url)
    }

    private func openInBrowser(_ url: URL) {
        if NSWorkspace.shared.open(url) {
            close()
        } else {
            actionError = "기본 브라우저를 열지 못했습니다."
        }
    }

    private func perform(_ destination: Destination) {
        switch destination {
        case .library(let location):
            if case .library(let open) = mode { open(location) }
        case .history(let kind):
            previousQuery = query
            historyKind = kind
            changeQuery("")
        case .historyEntry(let kind, let id):
            guard let entry = history.entries(kind).first(where: { $0.id == id }) else { return }
            if kind == .clipboard { history.restoreClipboard(entry) }
            else { history.openFile(entry) }
            if let failure = history.errors[kind] { actionError = failure }
            else { close() }
        case .openApplication(let application):
            if NSWorkspace.shared.open(URL(fileURLWithPath: application.path)) {
                close()
            } else {
                actionError = "‘\(application.displayName)’ 앱을 열지 못했습니다."
            }
        case .openWebAddress(let url):
            openInBrowser(url)
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
                actionError = error.localizedDescription
            }
        case .pasteTemplate(let id):
            runtime.run(templateID: id)
            close()
        case .copyValue(let value):
            do {
                try runtime.clipboard.copy(NSAttributedString(string: value))
                close()
            } catch {
                actionError = error.localizedDescription
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
    private let runtime: WookeyRuntime
    private let history: LocalHistoryStore
    private var window: SearchWindow?

    init(runtime: WookeyRuntime, history: LocalHistoryStore) {
        self.runtime = runtime
        self.history = history
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
        panel.title = "Wookey 검색창"
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
                .environment(history)
                .modifier(WookeyThemeScope())
        )
        panel.openSettings = { [weak self] event in
            NSApp.activate(ignoringOtherApps: true)
            guard NSApp.mainMenu?.performKeyEquivalent(with: event) == true else { return false }
            self?.close()
            return true
        }
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
        var openSettings: ((NSEvent) -> Bool)?

        override var canBecomeKey: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command, event.charactersIgnoringModifiers == ",",
               openSettings?(event) == true {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}


// Consume navigation commands at the field editor, where macOS handles arrows
// and Return before they reach SwiftUI. Keep the search state in the parent.
private struct WorkspaceSearchField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onWebSearch: () -> Void
    var onCancel: () -> Void
    var prompt: String

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = AutofocusingSearchField()
        field.font = WookeyTypography.native(size: 16)
        field.placeholderString = prompt
        field.setAccessibilityLabel("Wookey 검색어")
        field.controlSize = .large
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.placeholderString != prompt { field.placeholderString = prompt }
        let editor = field.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        if field.stringValue != text { field.stringValue = text }
        if let editor, editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
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
            case #selector(NSResponder.insertNewline(_:)):
                let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .control, .shift])
                if modifiers == .command { parent.onWebSearch() }
                else { parent.onSubmit() }
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
