import AppKit
import SwiftUI
import WookeyCore

enum SidebarSelection: Hashable {
    case workflowCollection
    case workflow(UUID)
    case linkCollection
    case link(UUID)
    case applications
    case application(String)
    case templateCollection
    case template(UUID)
    case layoutCollection
    case newLayout
    case layout(UUID)
    case clipboard
    case files

    var section: Self {
        switch self {
        case .workflow: .workflowCollection
        case .link: .linkCollection
        case .application: .applications
        case .template: .templateCollection
        case .newLayout, .layout: .layoutCollection
        case .clipboard: .files
        default: self
        }
    }

    static let sections: [Self] = [
        .workflowCollection, .linkCollection, .applications, .templateCollection, .layoutCollection, .files
    ]

    var title: String {
        switch section {
        case .workflowCollection: L10n.text("워크플로")
        case .linkCollection: L10n.text("링크")
        case .applications: L10n.text("앱")
        case .templateCollection: L10n.text("템플릿")
        case .layoutCollection: L10n.text("레이아웃")
        case .files: HistoryKind.files.title
        default: ""
        }
    }

    var symbol: String {
        switch section {
        case .workflowCollection: "bolt"
        case .linkCollection: "link"
        case .applications: "app"
        case .templateCollection: wookeyTemplateSymbol
        case .layoutCollection: "rectangle.3.group"
        case .files: HistoryKind.files.symbol
        default: ""
        }
    }
}

private struct WookeySidebar: View {
    @Environment(\.wookeyTheme) private var theme
    @FocusState private var focusedSection: SidebarSelection?
    var selected: SidebarSelection
    var navigate: (SidebarSelection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("보관함"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.bottom, 3)
                    .accessibilityAddTraits(.isHeader)

                ForEach(SidebarSelection.sections, id: \.self) { section in
                    row(section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(theme.sidebar)
        .accessibilityLabel(L10n.text("사이드바"))
    }

    private func row(_ section: SidebarSelection) -> some View {
        let isSelected = selected == section
        let ink = theme.accent
        return Button {
            navigate(section)
        } label: {
            HStack(spacing: 9) {
                WookeyActionIcon(symbol: section.symbol, tint: WookeyActionTint(symbol: section.symbol), size: 17)
                    .frame(width: 19)
                Text(section.title)
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ink : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
        }
        .buttonStyle(WookeyHoverButtonStyle(selected: isSelected, focused: focusedSection == section))
        .focusable()
        .focused($focusedSection, equals: section)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onKeyPress(.upArrow) { move(from: section, offset: -1) }
        .onKeyPress(.downArrow) { move(from: section, offset: 1) }
    }

    private func move(from section: SidebarSelection, offset: Int) -> KeyPress.Result {
        let sections = SidebarSelection.sections
        guard let current = sections.firstIndex(of: section),
              sections.indices.contains(current + offset) else { return .handled }
        let destination = sections[current + offset]
        focusedSection = destination
        navigate(destination)
        return .handled
    }
}

struct ContentView: View {
    var showSettings: () -> Void
    @Environment(\.wookeyTheme) private var theme
    private enum QuickCreate: Identifiable {
        case workflow, link

        var id: Self { self }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(WookeyRuntime.self) private var runtime
    @AppStorage(WookeyIconTheme.storageKey) private var iconTheme = WookeyIconTheme.threeDimensional
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var selection: SidebarSelection = .workflowCollection
    @State private var showOnboarding = false
    @State private var quickCreate: QuickCreate?
    @State private var showsNewTemplate = false
    @State private var showsSearch = false
    @State private var editingSession = UUID()

    var body: some View {
        NavigationSplitView {
            WookeySidebar(selected: selection.section) { selection = $0 }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let error = runtime.store.lastPersistenceError {
                    HStack(spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                        Spacer()
                        if runtime.store.needsRecovery {
                            Button(L10n.text("새로 시작")) {
                                runtime.store.acknowledgeRecovery()
                                runtime.saveAndReloadHotkeys()
                            }
                            .help(L10n.text("손상된 설정은 백업해 두고 현재 상태로 새로 시작합니다."))
                        } else {
                            Button(L10n.text("다시 저장")) { runtime.saveAndReloadHotkeys() }
                        }
                    }
                    .padding(16)
                    .background(WookeyActionTint.rose.ink(in: colorScheme).opacity(0.08))
                }
                detail
                if runtime.runner.runningWorkflowID != nil {
                    Divider()
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(runtime.runner.currentActionTitle ?? L10n.text("실행 준비 중"))
                            .font(.subheadline)
                            .lineLimit(1)
                        if !runtime.runner.queuedWorkflowIDs.isEmpty {
                            Text(L10n.text("대기 \(runtime.runner.queuedWorkflowIDs.count)개"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("실행 중지"), wookeyIcon: "stop.fill") { runtime.runner.cancel() }
                    }
                    .padding(.horizontal, WookeyPageMetrics.padding)
                    .padding(.vertical, 12)
                    .background(theme.panel)
                }
            }
            .background(theme.canvas)
        }
        .toolbarBackground(theme.panel, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.text("Wookey 검색"), wookeyIcon: "magnifyingglass") { showsSearch = true }
                    .labelStyle(.iconOnly)
                    .help(L10n.text("Wookey 검색 (⌘K)"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(L10n.text("새 워크플로"), systemImage: "bolt", action: addWorkflow)
                    Button(L10n.text("새 링크"), systemImage: "link", action: addLink)
                    Button(L10n.text("새 템플릿"), systemImage: wookeyTemplateSymbol, action: addTemplate)
                    Button(L10n.text("새 레이아웃"), systemImage: "rectangle.3.group", action: addLayout)
                } label: {
                    Label {
                        Text(L10n.text("새로 만들기"))
                    } icon: {
                        createMenuIcon
                    }
                    .labelStyle(.iconOnly)
                }
                .help(L10n.text("새로 만들기"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.text("설정"), wookeyIcon: "gearshape", action: showSettings)
                .labelStyle(.iconOnly)
                .help(L10n.text("설정 (⌘,)"))
            }
        }
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            createWorkflow: {
                guard !showOnboarding, !showsSearch, !showsNewTemplate, quickCreate == nil else { return }
                addWorkflow()
            },
            search: {
                guard !showOnboarding, !showsNewTemplate, quickCreate == nil else { return }
                showsSearch = true
            }
        ))
        .onAppear {
            if !didCompleteOnboarding { showOnboarding = true }
        }
        .onChange(of: selection, initial: true) { _, current in
            switch current {
            case .workflow, .link, .template, .layout: runtime.iCloudSync.setEditing(true, session: editingSession)
            default: runtime.iCloudSync.setEditing(false, session: editingSession)
            }
        }
        .onDisappear { runtime.iCloudSync.setEditing(false, session: editingSession) }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environment(runtime)
                .presentationBackground(theme.canvas)
        }
        .sheet(item: $quickCreate) { destination in
            QuickWorkflowView(
                initialKind: destination == .link ? .link : nil,
                onSave: { workflow in
                    _ = runtime.store.addWorkflow(workflow)
                    runtime.reloadHotkeys()
                    selection = destination == .link ? .linkCollection : .workflowCollection
                    quickCreate = nil
                },
                onAdvanced: {
                    selection = .workflow(runtime.store.addWorkflow())
                    quickCreate = nil
                }
            )
            .presentationBackground(theme.canvas)
        }
        .sheet(isPresented: $showsSearch) {
            WorkspaceSearchView(mode: .library { destination in
                selection = destination
                showsSearch = false
            })
            .presentationBackground(theme.canvas)
        }
        .sheet(isPresented: $showsNewTemplate) {
            NewTemplateView { id in
                selection = .template(id)
                showsNewTemplate = false
            }
            .presentationBackground(theme.canvas)
        }
    }

    private var createMenuIcon: Image {
        let asset = NSImage.Name(iconTheme.asset("WookeyCommandAdd"))
        guard let artwork = wookeyAssetBundle.image(forResource: asset) else {
            return Image(systemName: "plus")
        }
        // The native toolbar reads the NSImage size independently of SwiftUI layout.
        let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            artwork.draw(in: bounds)
            return true
        }
        return Image(nsImage: icon).renderingMode(.original)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .workflowCollection:
            WorkflowLibraryView(
                createWorkflow: addWorkflow,
                openWorkflow: { selection = .workflow($0) }
            )
        case .linkCollection:
            LinkLibraryView(open: { selection = .link($0) }, add: addLink)
        case .workflow(let id), .link(let id):
            let collection = selection.section
            if let binding = workflowBinding(id) {
                WorkflowEditorView(
                    workflow: binding,
                    onBack: { selection = collection },
                    onDelete: { deleteWorkflow(id, returnTo: collection) }
                )
                .id(id)
            } else {
                ContentUnavailableView(L10n.text("워크플로를 찾을 수 없습니다"), systemImage: "bolt.slash")
            }
        case .applications:
            ApplicationsView()
        case .application(let bundleID):
            ApplicationsView(initialSearch: bundleID)
                .id(bundleID)
        case .clipboard, .files:
            LocalHistoryView(initialKind: selection == .clipboard ? .clipboard : .files)
                .id(selection)
        case .templateCollection:
            TemplateLibraryView(
                templates: runtime.store.templates,
                open: { selection = .template($0) },
                add: addTemplate
            )
        case .template(let id):
            if let binding = templateBinding(id) {
                TemplateEditorView(
                    template: binding,
                    onBack: { selection = .templateCollection },
                    onDelete: { deleteTemplate(id) }
                )
                .id(id)
            } else {
                ContentUnavailableView(L10n.text("템플릿을 찾을 수 없습니다"), systemImage: "doc.badge.ellipsis")
            }
        case .layoutCollection:
            LayoutLibraryView(
                layouts: runtime.store.layouts,
                open: { selection = .layout($0) },
                add: addLayout
            )
        case .newLayout:
            NewLayoutEditor(
                onCancel: { selection = .layoutCollection },
                onSave: { layout in
                    guard runtime.store.addLayout(layout) else { return }
                    runtime.reloadHotkeys()
                    selection = .layout(layout.id)
                }
            )
        case .layout(let id):
            if let binding = layoutBinding(id) {
                LayoutEditorView(
                    layout: binding,
                    onBack: { selection = .layoutCollection },
                    onDelete: { deleteLayout(id) }
                )
                .id(id)
            } else {
                ContentUnavailableView(L10n.text("레이아웃을 찾을 수 없습니다"), systemImage: "rectangle.3.group")
            }
        }
    }

    private func workflowBinding(_ id: UUID) -> Binding<Workflow>? {
        guard let fallback = runtime.store.workflows.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { runtime.store.workflows.first(where: { $0.id == id }) ?? fallback },
            set: { updated in
                guard let index = runtime.store.workflows.firstIndex(where: { $0.id == id }) else { return }
                let previous = runtime.store.workflows[index]
                runtime.store.workflows[index] = updated
                runtime.store.save()
                if previous.shortcut != updated.shortcut || previous.isEnabled != updated.isEnabled {
                    runtime.reloadHotkeys()
                }
            }
        )
    }

    private func templateBinding(_ id: UUID) -> Binding<RichTemplate>? {
        guard let fallback = runtime.store.templates.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { runtime.store.templates.first(where: { $0.id == id }) ?? fallback },
            set: { updated in
                guard let index = runtime.store.templates.firstIndex(where: { $0.id == id }) else { return }
                runtime.store.templates[index] = updated
                runtime.store.save()
            }
        )
    }

    private func layoutBinding(_ id: UUID) -> Binding<WindowLayout>? {
        guard let fallback = runtime.store.layouts.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { runtime.store.layouts.first(where: { $0.id == id }) ?? fallback },
            set: { updated in
                guard let index = runtime.store.layouts.firstIndex(where: { $0.id == id }) else { return }
                let previous = runtime.store.layouts[index]
                runtime.store.layouts[index] = updated
                runtime.store.save()
                if previous.shortcut != updated.shortcut {
                    runtime.reloadHotkeys()
                }
            }
        )
    }

    private func addWorkflow() {
        quickCreate = .workflow
    }

    private func addLink() {
        quickCreate = .link
    }

    private func addTemplate() {
        showsNewTemplate = true
    }

    private func addLayout() {
        selection = .newLayout
    }

    private func deleteWorkflow(_ id: UUID, returnTo collection: SidebarSelection) {
        runtime.store.deleteWorkflow(id: id)
        runtime.reloadHotkeys()
        selection = collection
    }

    private func deleteTemplate(_ id: UUID) {
        runtime.store.deleteTemplate(id: id)
        runtime.reloadHotkeys()
        selection = .templateCollection
    }

    private func deleteLayout(_ id: UUID) {
        runtime.store.deleteLayout(id: id)
        runtime.reloadHotkeys()
        selection = .layoutCollection
    }
}

struct RunSummaryView: View {
    var summary: RunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    summary.failures.isEmpty ? L10n.text("완료") : L10n.text("실행을 완료하지 못했습니다"),
                    systemImage: summary.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(summary.failures.isEmpty ? Color.green : Color.orange)
                .font(.headline)
                Spacer()
                Text(summary.finishedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(summary.workflowName)
            ForEach(summary.failures) { failure in
                Text("\(failure.actionTitle) — \(failure.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LinkLibraryView: View {
    private struct Link: Identifiable {
        let workflow: Workflow
        let address: String
        var id: UUID { workflow.id }

        init?(_ workflow: Workflow) {
            guard workflow.actions.count == 1, case .openURL(let address)? = workflow.actions.first else { return nil }
            self.workflow = workflow
            self.address = address
        }
    }

    @Environment(WookeyRuntime.self) private var runtime
    @State private var searchText = ""
    var open: (UUID) -> Void
    var add: () -> Void

    var body: some View {
        let links = runtime.store.workflows.compactMap(Link.init)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = links.filter { link in
            query.isEmpty || link.workflow.name.localizedCaseInsensitiveContains(query)
                || link.address.localizedCaseInsensitiveContains(query)
                || link.workflow.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }

        LibraryLandingView(
            title: L10n.text("링크"),
            subtitle: L10n.text("자주 여는 주소를 저장하고 검색 키워드나 단축키로 실행하세요."),
            addTitle: L10n.text("링크 추가"),
            searchText: $searchText,
            isEmpty: links.isEmpty,
            hasSearchResults: !filtered.isEmpty,
            section: .linkCollection,
            emptyDescription: L10n.text("자주 방문하는 웹사이트의 주소를 추가해 보세요."),
            add: add
        ) {
            ForEach(filtered) { link in
                HStack(spacing: 4) {
                    LibraryItemButton(
                        title: link.workflow.name,
                        subtitle: ([link.address] + link.workflow.keywords).joined(separator: " · "),
                        systemImage: "link",
                        warning: runtime.hotkeys.registrationErrors[link.id],
                        action: { open(link.id) }
                    )
                    Button {
                        runtime.run(workflowID: link.id)
                    } label: {
                        WookeyActionIcon(symbol: "arrow.up.right", tint: .graphite, size: 14)
                    }
                    .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                    .accessibilityLabel(L10n.text("\(link.workflow.name) 링크 열기"))
                    .help(L10n.text("링크 열기"))
                    .disabled(runtime.runner.runningWorkflowID == link.id || runtime.runner.queuedWorkflowIDs.contains(link.id))
                    .padding(.trailing, 12)
                }
            }
        }
    }
}

private struct TemplateLibraryView: View {
    var templates: [RichTemplate]
    var open: (UUID) -> Void
    var add: () -> Void
    @State private var searchText = ""

    private var filteredTemplates: [RichTemplate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.plainText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        LibraryLandingView(
            title: L10n.text("템플릿"),
            subtitle: L10n.text("자주 쓰는 문장을 저장하고 워크플로에서 바로 사용합니다."),
            addTitle: L10n.text("템플릿 추가"),
            searchText: $searchText,
            isEmpty: templates.isEmpty,
            hasSearchResults: !filteredTemplates.isEmpty,
            section: .templateCollection,
            emptyDescription: L10n.text("자주 쓰는 문장과 이미지를 담은 첫 템플릿을 만들어 보세요."),
            add: add
        ) {
            ForEach(filteredTemplates) { template in
                LibraryItemButton(
                    title: template.name,
                    subtitle: template.plainText.isEmpty ? L10n.text("내용 없음") : template.plainText,
                    systemImage: wookeyTemplateSymbol,
                    action: { open(template.id) }
                )
            }
        }
    }
}

private struct LayoutLibraryView: View {
    @Environment(WookeyRuntime.self) private var runtime
    var layouts: [WindowLayout]
    var open: (UUID) -> Void
    var add: () -> Void
    @State private var searchText = ""

    private var filteredLayouts: [WindowLayout] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return layouts }
        return layouts.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        LibraryLandingView(
            title: L10n.text("레이아웃"),
            subtitle: L10n.text("앱 창의 위치와 크기를 한 번에 배치합니다."),
            addTitle: L10n.text("레이아웃 추가"),
            searchText: $searchText,
            isEmpty: layouts.isEmpty,
            hasSearchResults: !filteredLayouts.isEmpty,
            section: .layoutCollection,
            emptyDescription: L10n.text("함께 사용하는 앱을 추가하고 창을 배치할 위치를 정하세요."),
            add: add
        ) {
            ForEach(filteredLayouts) { layout in
                LibraryItemButton(
                    title: layout.name,
                    subtitle: L10n.text("\(layout.placements.count)개 앱 배치 · ")
                        + (layout.shortcut.steps.isEmpty ? L10n.text("단축키 미지정") : layout.shortcut.displayName),
                    systemImage: "rectangle.3.group",
                    warning: runtime.hotkeys.layoutRegistrationErrors[layout.id],
                    action: { open(layout.id) }
                )
            }
        }
    }
}

private struct LibraryLandingView<Content: View>: View {
    var title: String
    var subtitle: String
    var addTitle: String
    @Environment(\.wookeyTheme) private var theme
    @Binding var searchText: String
    var isEmpty: Bool
    var hasSearchResults: Bool
    var section: SidebarSelection
    var emptyDescription: String
    var add: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: WookeyPageMetrics.headerSpacing) {
                    WookeyPageHeader(title: title, subtitle: subtitle) {
                        Button(addTitle, wookeyIcon: "plus", action: add)
                            .buttonStyle(WookeyGlossyButtonStyle())
                            .controlSize(.large)
                    }
                    WookeySearchField(prompt: L10n.text("\(title) 검색"), text: $searchText)
                }
                if isEmpty {
                    ContentUnavailableView {
                        WookeyEmptyStateLabel(title: L10n.text("저장한 항목이 없습니다"), symbol: section.symbol)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button(addTitle, action: add)
                            .buttonStyle(WookeyGlossyButtonStyle())
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if !hasSearchResults {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 0) {
                        content
                    }
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary)
                    }
                }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(title)
    }
}

private struct LibraryItemButton: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var warning: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                WookeyActionIcon(
                    symbol: systemImage,
                    tint: WookeyActionTint(symbol: systemImage),
                    size: 24
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer()
                WookeyActionIcon(symbol: "chevron.right", tint: .neutral, size: 13)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
