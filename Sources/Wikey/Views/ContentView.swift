import AppKit
import SwiftUI
import WikeyCore

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
    case layout(UUID)

    var section: Self {
        switch self {
        case .workflow: .workflowCollection
        case .link: .linkCollection
        case .application: .applications
        case .template: .templateCollection
        case .layout: .layoutCollection
        default: self
        }
    }

    static let sections: [Self] = [.workflowCollection, .linkCollection, .applications, .templateCollection, .layoutCollection]

    var title: String {
        switch section {
        case .workflowCollection: "워크플로"
        case .linkCollection: "링크"
        case .applications: "앱"
        case .templateCollection: "템플릿"
        case .layoutCollection: "레이아웃"
        default: ""
        }
    }

    var symbol: String {
        switch section {
        case .workflowCollection: "bolt"
        case .linkCollection: "link"
        case .applications: "app"
        case .templateCollection: "doc.on.clipboard"
        case .layoutCollection: "rectangle.3.group"
        default: ""
        }
    }
}

private struct WikeySidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedSection: SidebarSelection?
    var selected: SidebarSelection
    var navigate: (SidebarSelection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("보관함")
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
        .accessibilityLabel("사이드바")
    }

    private func row(_ section: SidebarSelection) -> some View {
        let isSelected = selected == section
        let ink = Color.wikeyInk(in: colorScheme)
        return Button {
            navigate(section)
        } label: {
            HStack(spacing: 9) {
                WikeyActionIcon(symbol: section.symbol, tint: WikeyActionTint(symbol: section.symbol), size: 17)
                    .frame(width: 19)
                Text(section.title)
                    .font(.body.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? ink : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
        }
        .buttonStyle(WikeyHoverButtonStyle(selected: isSelected, focused: focusedSection == section))
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
    private enum QuickCreate: Identifiable {
        case workflow, link

        var id: Self { self }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(WikeyRuntime.self) private var runtime
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var selection: SidebarSelection = .workflowCollection
    @State private var showOnboarding = false
    @State private var quickCreate: QuickCreate?
    @State private var showsSearch = false
    @State private var editingSession = UUID()

    var body: some View {
        NavigationSplitView {
            WikeySidebar(selected: selection.section) { selection = $0 }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let error = runtime.store.lastPersistenceError {
                    HStack(spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                        Spacer()
                        Button("다시 저장") { runtime.saveAndReloadHotkeys() }
                    }
                    .padding(16)
                    .background(WikeyActionTint.rose.ink(in: colorScheme).opacity(0.08))
                }
                detail
                if runtime.runner.runningWorkflowID != nil {
                    Divider()
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(runtime.runner.currentActionTitle ?? "실행 준비 중")
                            .font(.subheadline)
                            .lineLimit(1)
                        if !runtime.runner.queuedWorkflowIDs.isEmpty {
                            Text("대기 \(runtime.runner.queuedWorkflowIDs.count)개")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("실행 중지", wikeyIcon: "stop.fill") { runtime.runner.cancel() }
                    }
                    .padding(.horizontal, WikeyPageMetrics.padding)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Wikey 검색", wikeyIcon: "magnifyingglass") { showsSearch = true }
                    .labelStyle(.iconOnly)
                    .help("Wikey 검색 (⌘K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("새 워크플로", wikeyIcon: "bolt", action: addWorkflow)
                    Button("새 링크", wikeyIcon: "link", action: addLink)
                    Button("새 템플릿", wikeyIcon: "doc.on.clipboard", action: addTemplate)
                    Button("새 레이아웃", wikeyIcon: "rectangle.3.group", action: addLayout)
                } label: {
                    WikeyControlLabel(title: "새로 만들기", symbol: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("새로 만들기")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    WikeyControlLabel(title: "설정", symbol: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("설정 (⌘,)")
            }
        }
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            createWorkflow: {
                guard !showOnboarding, !showsSearch, quickCreate == nil else { return }
                addWorkflow()
            },
            search: {
                guard !showOnboarding, quickCreate == nil else { return }
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
        }
        .sheet(isPresented: $showsSearch) {
            WorkspaceSearchView(mode: .library { destination in
                selection = destination
                showsSearch = false
            })
        }
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
                ContentUnavailableView("워크플로를 찾을 수 없습니다", systemImage: "bolt.slash")
            }
        case .applications:
            ApplicationsView()
        case .application(let bundleID):
            ApplicationsView(initialSearch: bundleID)
                .id(bundleID)
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
                ContentUnavailableView("템플릿을 찾을 수 없습니다", systemImage: "doc.badge.ellipsis")
            }
        case .layoutCollection:
            LayoutLibraryView(
                layouts: runtime.store.layouts,
                open: { selection = .layout($0) },
                add: addLayout
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
                ContentUnavailableView("레이아웃을 찾을 수 없습니다", systemImage: "rectangle.3.group")
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
                runtime.store.layouts[index] = updated
                runtime.saveAndReloadHotkeys()
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
        selection = .template(runtime.store.addTemplate())
    }

    private func addLayout() {
        selection = .layout(runtime.store.addLayout())
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
                    summary.failures.isEmpty ? "완료" : "실행을 완료하지 못했습니다",
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

    @Environment(WikeyRuntime.self) private var runtime
    @State private var searchText = ""
    var open: (UUID) -> Void
    var add: () -> Void

    var body: some View {
        let links = runtime.store.workflows.compactMap(Link.init)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = links.filter { link in
            query.isEmpty || link.workflow.name.localizedCaseInsensitiveContains(query)
                || link.address.localizedCaseInsensitiveContains(query)
                || link.workflow.keyword?.localizedCaseInsensitiveContains(query) == true
        }

        LibraryLandingView(
            title: "링크",
            subtitle: "자주 여는 주소를 저장하고 검색 키워드나 단축키로 실행하세요.",
            addTitle: "링크 추가",
            searchText: $searchText,
            isEmpty: links.isEmpty,
            hasSearchResults: !filtered.isEmpty,
            emptySymbol: "link",
            emptyDescription: "자주 방문하는 웹사이트의 주소를 추가해 보세요.",
            add: add
        ) {
            ForEach(filtered) { link in
                HStack(spacing: 4) {
                    LibraryItemButton(
                        title: link.workflow.name,
                        subtitle: [link.address, link.workflow.keyword].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "link",
                        warning: runtime.hotkeys.registrationErrors[link.id],
                        action: { open(link.id) }
                    )
                    Button {
                        runtime.run(workflowID: link.id)
                    } label: {
                        WikeyActionIcon(symbol: "arrow.up.right", tint: .graphite, size: 14)
                    }
                    .buttonStyle(WikeyGlossyButtonStyle(tint: .graphite, iconOnly: true))
                    .accessibilityLabel("\(link.workflow.name) 링크 열기")
                    .help("링크 열기")
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
            title: "템플릿",
            subtitle: "자주 쓰는 문장을 저장하고 워크플로에서 바로 사용합니다.",
            addTitle: "템플릿 추가",
            searchText: $searchText,
            isEmpty: templates.isEmpty,
            hasSearchResults: !filteredTemplates.isEmpty,
            emptySymbol: "doc.on.clipboard",
            emptyDescription: "자주 쓰는 문장과 이미지를 담은 첫 템플릿을 만들어 보세요.",
            add: add
        ) {
            ForEach(filteredTemplates) { template in
                LibraryItemButton(
                    title: template.name,
                    subtitle: template.plainText.isEmpty ? "내용 없음" : template.plainText,
                    systemImage: "doc.on.clipboard",
                    action: { open(template.id) }
                )
            }
        }
    }
}

private struct LayoutLibraryView: View {
    @Environment(WikeyRuntime.self) private var runtime
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
            title: "레이아웃",
            subtitle: "앱 창의 위치와 크기를 한 번에 배치합니다.",
            addTitle: "레이아웃 추가",
            searchText: $searchText,
            isEmpty: layouts.isEmpty,
            hasSearchResults: !filteredLayouts.isEmpty,
            emptySymbol: "rectangle.3.group",
            emptyDescription: "함께 사용하는 앱을 추가하고 창을 배치할 위치를 정하세요.",
            add: add
        ) {
            ForEach(filteredLayouts) { layout in
                LibraryItemButton(
                    title: layout.name,
                    subtitle: "\(layout.placements.count)개 앱 배치 · "
                        + (layout.shortcut.steps.isEmpty ? "단축키 미지정" : layout.shortcut.displayName),
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
    @Binding var searchText: String
    var isEmpty: Bool
    var hasSearchResults: Bool
    var emptySymbol: String
    var emptyDescription: String
    var add: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                WikeyPageHeader(title: title, subtitle: subtitle) {
                    Button(addTitle, wikeyIcon: "plus", action: add)
                        .wikeyPrimaryButtonStyle()
                        .controlSize(.large)
                }
                WikeySearchField(prompt: "\(title) 검색", text: $searchText)
                if isEmpty {
                    ContentUnavailableView {
                        Label("저장한 항목이 없습니다", systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button(addTitle, action: add)
                            .wikeyPrimaryButtonStyle()
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if !hasSearchResults {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVStack(spacing: 0) {
                        content
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary)
                    }
                }
            }
            .padding(WikeyPageMetrics.padding)
            .frame(maxWidth: WikeyPageMetrics.maximumWidth, alignment: .leading)
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
                WikeyActionIcon(
                    symbol: systemImage,
                    tint: WikeyActionTint(symbol: systemImage),
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
                WikeyActionIcon(symbol: "chevron.right", tint: .neutral, size: 13)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
