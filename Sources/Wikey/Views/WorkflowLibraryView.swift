import SwiftUI
import WikeyCore

struct WorkflowLibraryView: View {
    private enum Filter: String, CaseIterable {
        case all = "전체"
        case enabled = "활성"
        case disabled = "꺼짐"
        case conflicts = "단축키 오류"
    }

    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
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
                        WikeySearchField(prompt: "이름·단축키·동작 검색", text: $query)
                        Picker("워크플로 필터", selection: $filter) {
                            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
            }
            .padding(WikeyPageMetrics.padding)
            .frame(maxWidth: WikeyPageMetrics.maximumWidth)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let summary = runtime.lastRun {
                        if !summary.failures.isEmpty { latestRun(summary) }
                    }

                    if runtime.store.workflows.isEmpty {
                        ContentUnavailableView {
                            Label("첫 워크플로를 만들어 보세요", systemImage: "bolt")
                        } description: {
                            Text("앱 열기, 웹사이트 열기, 템플릿 붙여넣기 등의 동작을 원하는 순서로 추가하세요.")
                        }
                        .frame(maxWidth: .infinity, minHeight: 230)
                    } else if visibleWorkflows.isEmpty {
                        ContentUnavailableView {
                            Label("표시할 워크플로가 없습니다", systemImage: "magnifyingglass")
                        } actions: {
                            Button("검색 및 필터 초기화") {
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
                .padding(WikeyPageMetrics.padding)
                .frame(maxWidth: WikeyPageMetrics.maximumWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("워크플로")
    }

    private var libraryHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("워크플로")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("자주 하는 일을 단축키 하나로 실행하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("새 워크플로", systemImage: "plus", action: createWorkflow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 3)
            }
            Spacer(minLength: 0)
            WikeyMascot(size: 122)
                .background {
                    Circle()
                        .fill(colorScheme == .dark ? Color.wikeyInk(in: colorScheme).opacity(0.16) : .white.opacity(0.28))
                        .frame(width: 100, height: 100)
                }
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WikeyLavenderPanel())
    }

    private func latestRun(_ summary: RunSummary) -> some View {
        WikeySection(title: "최근 실행") {
            PlainPanel { RunSummaryView(summary: summary) }
        }
    }

    private func workflowList(_ workflows: [Workflow]) -> some View {
        LazyVStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("이름").frame(maxWidth: .infinity, alignment: .leading)
                Text("단축키").frame(width: 136, alignment: .leading)
                Text("실행").frame(width: 56)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.wikeyAccent.opacity(0.063))

            ForEach(workflows) { workflow in
                Divider()
                WorkflowLibraryRow(
                    workflow: workflow,
                    conflict: runtime.hotkeys.registrationErrors[workflow.id],
                    open: { openWorkflow(workflow.id) }
                )
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary)
        }
    }
}

private struct WorkflowLibraryRow: View {
    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    var workflow: Workflow
    var conflict: String?
    var open: () -> Void

    private var executionStatus: String? {
        if runtime.runner.runningWorkflowID == workflow.id { return "실행 중" }
        if runtime.runner.queuedWorkflowIDs.contains(workflow.id) { return "대기 중" }
        return nil
    }

    private var iconForeground: Color {
        guard workflow.isEnabled else { return .secondary }
        return .wikeyInk(in: colorScheme)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: workflow.isEnabled ? "bolt.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconForeground)
                        .frame(width: 34, height: 34)
                        .background(
                            workflow.isEnabled
                                ? Color.wikeyAccent.opacity(colorScheme == .dark ? 0.30 : 0.11)
                                : Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workflow.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(executionStatus ?? "\(workflow.actions.count)개 동작" + (workflow.isEnabled ? "" : " · 꺼짐"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if let conflict {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel(conflict)
                                .help(conflict)
                        }
                        ShortcutBadge(
                            text: workflow.shortcut.steps.isEmpty ? "미지정" : workflow.shortcut.displayName,
                            isMuted: workflow.shortcut.steps.isEmpty || !workflow.isEnabled
                        )
                    }
                    .frame(width: 136, alignment: .leading)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(workflow.name) 편집")
            .accessibilityLabel("\(workflow.name) 편집")

            Button {
                runtime.run(workflowID: workflow.id)
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 24)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.wikeyInk(in: colorScheme))
            .disabled(workflow.actions.isEmpty || executionStatus != nil)
            .help("워크플로 실행")
            .accessibilityLabel("\(workflow.name) 실행")
            .frame(width: 56)
        }
        .padding(.horizontal, 16)
        .background(isHovering ? Color.wikeyAccent.opacity(0.075) : .clear)
        .onHover { isHovering = $0 }
    }
}
