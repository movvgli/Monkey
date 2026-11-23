import AppKit
import SwiftUI
import WikeyCore

enum SidebarSelection: Hashable {
    case workflowCollection
    case workflow(UUID)
    case applications
    case application(String)
    case templateCollection
    case template(UUID)
    case layoutCollection
    case layout(UUID)

    var section: Self {
        switch self {
        case .workflow: .workflowCollection
        case .application: .applications
        case .template: .templateCollection
        case .layout: .layoutCollection
        default: self
        }
    }

    static let sections: [Self] = [.workflowCollection, .applications, .templateCollection, .layoutCollection]

    var title: String {
        switch section {
        case .workflowCollection: "워크플로"
        case .applications: "앱"
        case .templateCollection: "템플릿"
        case .layoutCollection: "레이아웃"
        default: ""
        }
    }

    var symbol: String {
        switch section {
        case .workflowCollection: "bolt"
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
        .background(Color.wikeyAccent.opacity(colorScheme == .dark ? 0.07 : 0.035))
        .accessibilityLabel("사이드바")
    }

    private func row(_ section: SidebarSelection) -> some View {
        let isSelected = selected == section
        let ink = Color.wikeyInk(in: colorScheme)
        let shape = RoundedRectangle(cornerRadius: 9)

        return Button {
            navigate(section)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: 19)
                    .accessibilityHidden(true)
                Text(section.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? ink : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(ink.opacity(isSelected ? (colorScheme == .dark ? 0.19 : 0.13) : 0), in: shape)
            .overlay {
                if focusedSection == section {
                    shape.strokeBorder(ink, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
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
    @Environment(WikeyRuntime.self) private var runtime
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var selection: SidebarSelection = .workflowCollection
    @State private var showOnboarding = false
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
                            .foregroundStyle(.red)
                        Spacer()
                        Button("다시 저장") { runtime.saveAndReloadHotkeys() }
                    }
                    .padding(16)
                    .background(Color.red.opacity(0.08))
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
                        Button("실행 중지", systemImage: "stop.fill") { runtime.runner.cancel() }
                    }
                    .padding(.horizontal, WikeyPageMetrics.padding)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Wikey 검색", systemImage: "magnifyingglass") { showsSearch = true }
                    .help("Wikey 검색 (⌘K)")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("새 워크플로", systemImage: "bolt", action: addWorkflow)
                    Button("새 템플릿", systemImage: "doc.on.clipboard", action: addTemplate)
                    Button("새 레이아웃", systemImage: "rectangle.3.group", action: addLayout)
                } label: {
                    Label("새로 만들기", systemImage: "plus")
                }
                .help("새로 만들기")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("설정", systemImage: "gearshape")
                }
                .help("설정 (⌘,)")
            }
        }
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            createWorkflow: {
                guard !showOnboarding, !showsSearch else { return }
                addWorkflow()
            },
            search: {
                guard !showOnboarding else { return }
                showsSearch = true
            }
        ))
        .onAppear {
            if !didCompleteOnboarding { showOnboarding = true }
        }
        .onChange(of: selection, initial: true) { _, current in
            switch current {
            case .workflow, .template, .layout: runtime.iCloudSync.setEditing(true, session: editingSession)
            default: runtime.iCloudSync.setEditing(false, session: editingSession)
            }
        }
        .onDisappear { runtime.iCloudSync.setEditing(false, session: editingSession) }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .environment(runtime)
        }
        .sheet(isPresented: $showsSearch) {
            WorkspaceSearchView { destination in
                selection = destination
                showsSearch = false
            }
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
        case .workflow(let id):
            if let binding = workflowBinding(id) {
                WorkflowEditorView(
                    workflow: binding,
                    onBack: { selection = .workflowCollection },
                    onDelete: { deleteWorkflow(id) }
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
        selection = .workflow(runtime.store.addWorkflow())
    }

    private func addTemplate() {
        selection = .template(runtime.store.addTemplate())
    }

    private func addLayout() {
        selection = .layout(runtime.store.addLayout())
    }

    private func deleteWorkflow(_ id: UUID) {
        runtime.store.deleteWorkflow(id: id)
        runtime.reloadHotkeys()
        selection = .workflowCollection
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
                    Button(addTitle, systemImage: "plus", action: add)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                WikeySearchField(prompt: "\(title) 검색", text: $searchText)
                if isEmpty {
                    ContentUnavailableView {
                        Label("아직 \(title)이 없습니다", systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        Button(addTitle, action: add)
                            .buttonStyle(.borderedProminent)
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
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
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
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
