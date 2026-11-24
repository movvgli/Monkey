import SwiftUI
import WookeyCore

private enum WorkflowListMetrics {
    static let horizontalPadding: CGFloat = 10
    static let shortcutWidth: CGFloat = 132
    static let playWidth: CGFloat = 32
    static let spacing: CGFloat = 12
}

struct WorkflowLibraryView: View {
    private enum Filter: String, CaseIterable {
        case all = "전체"
        case enabled = "활성"
        case disabled = "꺼짐"
        case conflicts = "단축키 오류"
    }

    @Environment(WookeyRuntime.self) private var runtime
    @SceneStorage("workflowFilter") private var filter: Filter = .all
    @SceneStorage("workflowQuery") private var query = ""
    var createWorkflow: () -> Void
    var openWorkflow: (UUID) -> Void

    private var visibleWorkflows: [Workflow] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return runtime.store.workflows.filter { workflow in
            guard search.isEmpty
                    || workflow.name.localizedCaseInsensitiveContains(search)
                    || workflow.shortcut.displayName.localizedCaseInsensitiveContains(search)
                    || workflow.actions.contains(where: { $0.title.localizedCaseInsensitiveContains(search) })
            else { return false }

            switch filter {
            case .all: return true
            case .enabled: return workflow.isEnabled
            case .disabled: return !workflow.isEnabled
            case .conflicts: return runtime.hotkeys.registrationErrors[workflow.id] != nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                libraryHeader

                if !runtime.store.workflows.isEmpty {
                    HStack(spacing: 16) {
                        WookeySearchField(prompt: L10n.text("이름·단축키·동작 검색"), text: $query)
                        WookeyFilterPicker(title: L10n.text("워크플로 필터"), selection: $filter, options: Filter.allCases) {
                            L10n.label($0.rawValue)
                        }
                    }
                }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let summary = runtime.lastRun {
                        if !summary.failures.isEmpty { latestRun(summary) }
                    }

                    if runtime.store.workflows.isEmpty {
                        ContentUnavailableView {
                            WookeyEmptyStateLabel(title: L10n.text("첫 워크플로를 만들어 보세요"), symbol: SidebarSelection.workflowCollection.symbol)
                        } description: {
                            Text(L10n.text("앱 열기, 웹사이트 열기, 템플릿 붙여넣기 등의 동작을 원하는 순서로 추가하세요."))
                        }
                        .frame(maxWidth: .infinity, minHeight: 230)
                    } else if visibleWorkflows.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.text("표시할 워크플로가 없습니다"), systemImage: "magnifyingglass")
                        } actions: {
                            Button(L10n.text("검색 및 필터 초기화")) {
                                query = ""
                                filter = .all
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 230)
                    } else {
                        workflowList(visibleWorkflows)
                    }

                    if let summary = runtime.lastRun, summary.failures.isEmpty {
                        latestRun(summary)
                    }
                }
                .padding(WookeyPageMetrics.padding)
                .frame(maxWidth: WookeyPageMetrics.maximumWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L10n.text("워크플로"))
    }

    private var libraryHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("워크플로"))
                    .font(.pretendard(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.text("자주 하는 일을 단축키 하나로 실행하세요."))
                    .font(.pretendard(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L10n.text("새 워크플로"), wookeyIcon: "plus", action: createWorkflow)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
            WookeyMascot(size: 122)
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WookeyGlossyPanel(radius: 24))
    }

    private func latestRun(_ summary: RunSummary) -> some View {
        WookeySection(title: L10n.text("최근 실행")) {
            PlainPanel { RunSummaryView(summary: summary) }
        }
    }

    private func workflowList(_ workflows: [Workflow]) -> some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: WorkflowListMetrics.spacing) {
                Text(L10n.text("이름")).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("단축키")).frame(width: WorkflowListMetrics.shortcutWidth, alignment: .leading)
                Text(L10n.text("실행")).frame(width: WorkflowListMetrics.playWidth)
            }
            .font(.pretendard(.caption, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, WorkflowListMetrics.horizontalPadding)
            .padding(.bottom, 8)

            Divider()

            ForEach(workflows) { workflow in
                WorkflowLibraryRow(
                    workflow: workflow,
                    conflict: runtime.hotkeys.registrationErrors[workflow.id],
                    open: { openWorkflow(workflow.id) }
                )

                if workflow.id != workflows.last?.id {
                    Divider().opacity(0.5)
                }
            }
        }
    }
}

private struct WorkflowLibraryRow: View {
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    var workflow: Workflow
    var conflict: String?
    var open: () -> Void

    private var executionStatus: String? {
        if runtime.runner.runningWorkflowID == workflow.id { return L10n.text("실행 중") }
        if runtime.runner.queuedWorkflowIDs.contains(workflow.id) { return L10n.text("대기 중") }
        return nil
    }

    private var detail: String? {
        if let executionStatus { return executionStatus }
        if !workflow.isEnabled { return L10n.text("단축키 꺼짐") }
        switch workflow.actions.count {
        case 0: return L10n.text("동작 없음")
        case 1: return nil
        default: return L10n.text("\(workflow.actions.count)개 동작")
        }
    }

    var body: some View {
        HStack(spacing: WorkflowListMetrics.spacing) {
            editButton
            runButton
        }
        .padding(.horizontal, WorkflowListMetrics.horizontalPadding)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.wookeyInk(in: colorScheme).opacity(0.06) : .clear)
        }
        .onHover { isHovering = $0 }
    }

    private var editButton: some View {
        let icon = workflow.wookeyIcon
        return Button(action: open) {
            HStack(spacing: WorkflowListMetrics.spacing) {
                HStack(spacing: 10) {
                    WookeyActionIcon(symbol: icon.symbol, tint: icon.tint)

                    Text(workflow.name)
                        .font(.pretendard(.body))
                        .lineLimit(1)
                        .layoutPriority(1)

                    if let detail {
                        Text(detail)
                            .font(.pretendard(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                shortcut
                    .frame(width: WorkflowListMetrics.shortcutWidth, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("\(workflow.name) 편집"))
        .accessibilityLabel(L10n.text("\(workflow.name) 편집"))
    }

    private var shortcut: some View {
        HStack(spacing: 6) {
            if let conflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(conflict)
                    .help(conflict)
            }

            if workflow.shortcut.steps.isEmpty {
                Text("—")
                    .font(.pretendard(.caption))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.text("단축키 미지정"))
            } else {
                ShortcutBadge(text: workflow.shortcut.displayName, isMuted: !workflow.isEnabled)
            }
        }
    }

    private var runButton: some View {
        Button {
            runtime.run(workflowID: workflow.id)
        } label: {
            WookeyActionIcon(symbol: "play.fill", tint: .accent, size: 14)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
        .controlSize(.small)
        .frame(width: WorkflowListMetrics.playWidth)
        .disabled(workflow.actions.isEmpty || executionStatus != nil)
        .help(L10n.text("워크플로 실행"))
        .accessibilityLabel(L10n.text("\(workflow.name) 실행"))
    }
}
