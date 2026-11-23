import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WikeyCore

struct WorkflowEditorView: View {
    @Environment(WikeyRuntime.self) private var runtime
    @Binding var workflow: Workflow
    var onBack: () -> Void
    var onDelete: () -> Void

    @State private var showsShortcutEditor = false
    @State private var keywordDraft = ""
    @State private var showsActionPicker = false
    @State private var pendingAction: WorkflowActionPicker.Option?
    @State private var showsURLSetup = false
    @State private var showsLayoutSetup = false
    @State private var selectedLayoutID: UUID?
    @State private var newURL = ""
    @State private var showsDeleteConfirmation = false
    @State private var showsTemplateActionSetup = false
    @State private var selectedTemplateID: UUID?
    @State private var selectedTemplateMode: TemplateDeliveryMode = .copyAndPaste
    @State private var showsWorkflowActionSetup = false
    @State private var selectedWorkflowID: UUID?

    private var isRunning: Bool {
        runtime.runner.runningWorkflowID == workflow.id
    }

    private var availableReferencedWorkflows: [Workflow] {
        runtime.store.workflows.filter { candidate in
            !WorkflowDependencyGraph.wouldCreateCycle(
                from: workflow.id,
                to: candidate.id,
                in: runtime.store.workflows
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        shortcutSummary

                        VStack(alignment: .leading, spacing: 0) {
                            Text("실행 순서")
                                .font(.headline)
                                .padding(.bottom, 14)

                            if workflow.actions.isEmpty {
                                EmptyActionsView()
                            } else {
                                ForEach(Array(workflow.actions.enumerated()), id: \.offset) { index, fallback in
                                    FlowActionRow(
                                        number: index + 1,
                                        isLast: index == workflow.actions.count - 1,
                                        action: Binding(
                                            get: {
                                                workflow.actions.indices.contains(index)
                                                    ? workflow.actions[index]
                                                    : fallback
                                            },
                                            set: { updated in
                                                guard workflow.actions.indices.contains(index) else { return }
                                                workflow.actions[index] = updated
                                            }
                                        ),
                                        templates: runtime.store.templates,
                                        layouts: runtime.store.layouts,
                                        workflows: runtime.store.workflows,
                                        currentWorkflowID: workflow.id,
                                        moveUp: { move(index, offset: -1) },
                                        moveDown: { move(index, offset: 1) },
                                        delete: {
                                            guard workflow.actions.indices.contains(index) else { return }
                                            workflow.actions.remove(at: index)
                                        },
                                        canMoveUp: index > 0,
                                        canMoveDown: index < workflow.actions.count - 1
                                    )
                                    .id(index)
                                }
                            }

                            if !workflow.actions.isEmpty {
                                Button("다음 동작 추가", systemImage: "plus") { showsActionPicker = true }
                                    .buttonStyle(WikeyPastelButtonStyle())
                                    .padding(.leading, 48)
                                    .padding(.top, 5)
                            }
                        }
                        .padding(.top, 20)

                        if let summary = runtime.lastRun, summary.workflowID == workflow.id {
                            PlainPanel { RunSummaryView(summary: summary) }
                                .padding(.top, 24)
                        }
                    }
                    .padding(WikeyPageMetrics.padding)
                    .frame(maxWidth: WikeyPageMetrics.maximumWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: workflow.actions.count) { previous, current in
                    if current > previous {
                        withAnimation(.easeOut(duration: 0.2)) { scroll.scrollTo(current - 1, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                WikeySaveStatus()
                Spacer()
                Text("\(workflow.actions.count)개 동작")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    runtime.run(workflowID: workflow.id)
                } label: {
                    if isRunning || runtime.runner.queuedWorkflowIDs.contains(workflow.id) {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(isRunning ? "실행 중" : "대기 중")
                        }
                    } else {
                        Label("워크플로 실행", systemImage: "play.fill")
                    }
                }
                .buttonStyle(WikeyPastelButtonStyle(tint: .mint))
                .disabled(workflow.actions.isEmpty || isRunning || runtime.runner.queuedWorkflowIDs.contains(workflow.id))
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, WikeyPageMetrics.padding)
            .padding(.vertical, 13)
            .background(.bar)
        }
        .navigationTitle(workflow.name)
        .sheet(isPresented: $showsActionPicker, onDismiss: addPickedAction) {
            WorkflowActionPicker(
                templatesAvailable: !runtime.store.templates.isEmpty,
                layoutsAvailable: !runtime.store.layouts.isEmpty,
                workflowsAvailable: !availableReferencedWorkflows.isEmpty
            ) { option in
                pendingAction = option
                showsActionPicker = false
            }
        }
        .sheet(isPresented: $showsURLSetup) {
            WorkflowActionSetupSheet(
                title: "웹사이트 열기", canAdd: validWebURL != nil,
                cancel: { showsURLSetup = false }
            ) {
                guard let validWebURL else { return }
                workflow.actions.append(.openURL(validWebURL))
                showsURLSetup = false
            } content: {
                TextField("웹사이트 주소", text: $newURL, prompt: Text("https://example.com"))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .sheet(isPresented: $showsLayoutSetup) {
            WorkflowActionSetupSheet(
                title: "창 레이아웃 적용", canAdd: selectedLayoutID != nil,
                cancel: { showsLayoutSetup = false }
            ) {
                guard let selectedLayoutID, runtime.store.layouts.contains(where: { $0.id == selectedLayoutID })
                else { return }
                workflow.actions.append(.applyLayout(layoutID: selectedLayoutID))
                showsLayoutSetup = false
            } content: {
                Picker("레이아웃", selection: $selectedLayoutID) {
                    Text("레이아웃 선택").tag(nil as UUID?)
                    ForEach(runtime.store.layouts) { layout in
                        Text(layout.name).tag(Optional(layout.id))
                    }
                }
            }
        }
        .confirmationDialog(
            "이 워크플로를 삭제할까요?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive, action: onDelete)
            Button("취소", role: .cancel) {}
        } message: {
            Text("다른 워크플로에서 이 워크플로를 실행하는 동작도 함께 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
        .sheet(isPresented: $showsTemplateActionSetup) {
            TemplateActionSetupView(
                templates: runtime.store.templates,
                selectedTemplateID: $selectedTemplateID,
                selectedMode: $selectedTemplateMode,
                onCancel: { showsTemplateActionSetup = false },
                onAdd: addSelectedTemplateAction
            )
        }
        .sheet(isPresented: $showsWorkflowActionSetup) {
            WorkflowReferenceSetupView(
                workflows: availableReferencedWorkflows,
                selectedWorkflowID: $selectedWorkflowID,
                onCancel: { showsWorkflowActionSetup = false },
                onAdd: addSelectedWorkflowAction
            )
        }
    }

    private var editorHeader: some View {
        WikeyEditorHeader(
            title: $workflow.name,
            subtitle: "동작을 위에서부터 순서대로 실행합니다.",
            onBack: onBack
        ) {
            Button("동작 추가", systemImage: "plus") { showsActionPicker = true }
                .buttonStyle(WikeyPastelButtonStyle())
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("동작 추가 (⇧⌘D)")
            WikeyDeleteButton(title: "워크플로 삭제…") {
                showsDeleteConfirmation = true
            }
        }
    }

    private var shortcutSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("단축키")
                    .font(.headline)
                ShortcutBadge(
                    text: workflow.shortcut.steps.isEmpty ? "미지정" : workflow.shortcut.displayName,
                    isMuted: workflow.shortcut.steps.isEmpty
                )
                Spacer()
                Toggle("단축키 활성", isOn: $workflow.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("끄면 이 워크플로의 전역 단축키를 해제합니다.")
                Button(workflow.shortcut.steps.isEmpty ? "지정" : "변경", systemImage: "keyboard") {
                    showsShortcutEditor.toggle()
                }
                .buttonStyle(WikeyPastelButtonStyle(tint: .periwinkle))
                .popover(isPresented: $showsShortcutEditor, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("단축키 변경")
                            .font(.headline)
                        ShortcutRecorderView(shortcut: $workflow.shortcut)
                    }
                    .padding(20)
                    .frame(width: 480)
                }
            }

            if let error = runtime.hotkeys.registrationErrors[workflow.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()
            WorkflowKeywordField(keyword: $keywordDraft, workflowID: workflow.id)
                .frame(maxWidth: 340)
                .onChange(of: workflow.keyword, initial: true) { _, saved in
                    if WorkflowKeyword.normalized(keywordDraft) != saved { keywordDraft = saved ?? "" }
                }
                .onChange(of: keywordDraft) { _, value in
                    guard WorkflowKeyword.validationMessage(for: value, excluding: workflow.id, in: runtime.store.workflows) == nil else { return }
                    let keyword = WorkflowKeyword.normalized(value)
                    if workflow.keyword != keyword { workflow.keyword = keyword }
                }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(WikeyLavenderPanel(radius: 16))
    }

    private var validWebURL: String? {
        let input = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return input
    }

    private func addPickedAction() {
        guard let option = pendingAction else { return }
        pendingAction = nil
        switch option {
        case .app: chooseApplication()
        case .file:
            QuickWorkflowTargetPicker.file { url in
                workflow.actions.append(.openFile(path: url.path))
            }
        case .website:
            newURL = ""
            showsURLSetup = true
        case .enter: workflow.actions.append(.pressKey(.enter))
        case .shiftEnter: workflow.actions.append(.pressKey(.shiftEnter))
        case .wait: workflow.actions.append(.wait(seconds: 1))
        case .template: beginTemplateActionSetup()
        case .images:
            if let paths = chooseFiles(title: "붙여넣을 이미지 선택", contentType: .image) {
                workflow.actions.append(.pasteImages(filePaths: paths))
            }
        case .files:
            if let paths = chooseFiles(title: "붙여넣을 파일 선택", contentType: .item) {
                workflow.actions.append(.pasteFiles(filePaths: paths))
            }
        case .workflow:
            selectedWorkflowID = nil
            showsWorkflowActionSetup = true
        case .layout:
            selectedLayoutID = nil
            showsLayoutSetup = true
        }
    }

    private func move(_ index: Int, offset: Int) {
        let destination = index + offset
        guard workflow.actions.indices.contains(destination) else { return }
        workflow.actions.swapAt(index, destination)
    }

    private func beginTemplateActionSetup() {
        selectedTemplateID = nil
        selectedTemplateMode = .copyAndPaste
        showsTemplateActionSetup = true
    }

    private func addSelectedTemplateAction() {
        guard let selectedTemplateID,
              runtime.store.templates.contains(where: { $0.id == selectedTemplateID }) else { return }
        workflow.actions.append(
            .copyTemplate(templateID: selectedTemplateID, mode: selectedTemplateMode)
        )
        showsTemplateActionSetup = false
    }

    private func addSelectedWorkflowAction() {
        guard let selectedWorkflowID,
              availableReferencedWorkflows.contains(where: { $0.id == selectedWorkflowID }) else { return }
        workflow.actions.append(.runWorkflow(workflowID: selectedWorkflowID))
        showsWorkflowActionSetup = false
    }

    private func chooseApplication() {
        QuickWorkflowTargetPicker.application { app in
            workflow.actions.append(.launchApplication(bundleIdentifier: app.id, displayName: app.name))
        }
    }

    private func chooseFiles(title: String, contentType: UTType) -> [String]? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return nil }
        let paths = panel.urls.map(\.path)
        return paths.isEmpty ? nil : paths
    }
}

private struct TemplateActionSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    var templates: [RichTemplate]
    @Binding var selectedTemplateID: UUID?
    @Binding var selectedMode: TemplateDeliveryMode
    var onCancel: () -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("템플릿 붙여넣기 추가")
                    .font(.title2.weight(.semibold))
                Text("붙여넣을 템플릿과 실행 방식을 선택하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("붙여넣을 템플릿")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(templates) { template in
                                templateButton(template)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("실행 방식")
                            .font(.headline)
                        Picker("실행 방식", selection: $selectedMode) {
                            ForEach(TemplateDeliveryMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        Text(modeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("동작 추가", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedTemplateID == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(width: 520, height: 480)
    }

    private func templateButton(_ template: RichTemplate) -> some View {
        let isSelected = selectedTemplateID == template.id

        return Button {
            selectedTemplateID = template.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.wikeyInk(in: colorScheme))
                    .frame(width: 38, height: 38)
                    .background(Color.wikeyInk(in: colorScheme).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(template.plainText.isEmpty ? "내용 없음" : template.plainText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Color.wikeyInk(in: colorScheme) : Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.wikeyInk(in: colorScheme).opacity(0.08) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.wikeyInk(in: colorScheme).opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.35),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name) 템플릿")
        .accessibilityValue(isSelected ? "선택됨" : "선택 안 됨")
    }

    private var modeDescription: String {
        switch selectedMode {
        case .copyOnly:
            "내용을 클립보드에 복사하고 다음 동작으로 넘어갑니다."
        case .copyAndPaste:
            "내용을 복사한 뒤 현재 입력 위치에 자동으로 붙여넣습니다."
        }
    }
}

private struct FlowCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 10, y: 3)
    }
}

private struct EmptyActionsView: View {
    var body: some View {
        HStack(spacing: 14) {
            WikeyMascot(size: 66)
            VStack(alignment: .leading, spacing: 3) {
                Text("첫 동작을 추가해 보세요")
                    .font(.headline)
                Text("앱, 키 입력, 템플릿, 이미지, 파일과 다른 워크플로를 순서대로 연결할 수 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WikeyLavenderPanel(radius: 17))
    }
}

private struct FlowActionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var number: Int
    var isLast: Bool
    @Binding var action: WorkflowAction
    var templates: [RichTemplate]
    var layouts: [WindowLayout]
    var workflows: [Workflow]
    var currentWorkflowID: UUID
    var moveUp: () -> Void
    var moveDown: () -> Void
    var delete: () -> Void
    var canMoveUp: Bool
    var canMoveDown: Bool

    @State private var showsEditor = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FlowMarker(number: number, endsFlow: isLast)

            HStack(spacing: 16) {
                Button { showsEditor = true } label: {
                    HStack(spacing: 16) {
                        ActionIcon(action: action)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(actionTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(actionSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 16)
                        WikeyActionIcon(symbol: "slider.horizontal.3", tint: .lavender, size: 36)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("동작 세부 설정")
                Menu("동작 메뉴", systemImage: "ellipsis") {
                    Button("세부 설정…", systemImage: "slider.horizontal.3") {
                        showsEditor = true
                    }
                    Button("위로 이동", systemImage: "arrow.up", action: moveUp)
                        .disabled(!canMoveUp)
                    Button("아래로 이동", systemImage: "arrow.down", action: moveDown)
                        .disabled(!canMoveDown)
                    Divider()
                    Button("삭제", systemImage: "trash", role: .destructive, action: delete)
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .tint(Color.wikeyInk(in: colorScheme))
                .frame(width: 36, height: 36)
                .background(Color.wikeyInk(in: colorScheme).opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("동작 메뉴")
                .popover(isPresented: $showsEditor, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(actionTitle)
                            .font(.headline)
                        actionEditor
                        Divider()
                        HStack {
                            Button("위로 이동", systemImage: "arrow.up") {
                                showsEditor = false
                                moveUp()
                            }
                            .buttonStyle(WikeyPastelButtonStyle(tint: .periwinkle))
                            .disabled(!canMoveUp)
                            Button("아래로 이동", systemImage: "arrow.down") {
                                showsEditor = false
                                moveDown()
                            }
                            .buttonStyle(WikeyPastelButtonStyle(tint: .periwinkle))
                            .disabled(!canMoveDown)
                            Spacer()
                            Button("삭제", systemImage: "trash", role: .destructive) {
                                showsEditor = false
                                delete()
                            }
                            .buttonStyle(WikeyPastelButtonStyle(tint: .rose))
                        }
                    }
                    .padding(20)
                    .frame(width: 440)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 66)
            .background(FlowCardBackground())
            .padding(.bottom, 10)
        }
    }

    private var actionTitle: String {
        switch action {
        case .launchApplication: "앱 열기"
        case .copyTemplate: "템플릿 붙여넣기"
        case .openURL: "링크 열기"
        case .openFile: "파일 열기"
        case .applyLayout: "창 배치"
        case .pressKey(let key): "\(key.title) 입력"
        case .wait: "잠시 기다리기"
        case .runWorkflow: "워크플로 실행"
        case .pasteImages: "이미지 붙여넣기"
        case .pasteFiles: "파일 붙여넣기"
        }
    }

    private var actionSubtitle: String {
        switch action {
        case .launchApplication(let bundleID, let name):
            return name.isEmpty ? bundleID : name
        case .copyTemplate(let templateID, let mode):
            let name = templates.first(where: { $0.id == templateID })?.name ?? "템플릿 선택"
            return "\(name) · \(mode.title)"
        case .openURL(let url):
            return URL(string: url)?.host ?? url
        case .openFile(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .applyLayout(let layoutID):
            return layouts.first(where: { $0.id == layoutID })?.name ?? "레이아웃 선택"
        case .pressKey(let key):
            return key == .enter ? "현재 앱에 Enter 키를 입력합니다." : "현재 앱에 Shift + Enter 키를 입력합니다."
        case .wait(let seconds):
            return "\(seconds.formatted(.number.precision(.fractionLength(0...1))))초 후 다음 동작을 실행합니다."
        case .runWorkflow(let workflowID):
            return workflows.first(where: { $0.id == workflowID })?.name ?? "워크플로 선택"
        case .pasteImages(let filePaths):
            return selectedFileSummary(filePaths, itemName: "이미지")
        case .pasteFiles(let filePaths):
            return selectedFileSummary(filePaths, itemName: "파일")
        }
    }

    @ViewBuilder
    private var actionEditor: some View {
        switch action {
        case .launchApplication(let bundleID, let name):
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("앱 변경…") {
                    let panel = NSOpenPanel()
                    panel.title = "실행할 앱 선택"
                    panel.allowedContentTypes = [.application]
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
                    guard panel.runModal() == .OK, let url = panel.url,
                          let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
                    let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    action = .launchApplication(bundleIdentifier: identifier, displayName: displayName)
                }
            }

        case .openFile(let path):
            VStack(alignment: .leading, spacing: 8) {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc")
                    .lineLimit(1)
                Button("파일 변경…") {
                    QuickWorkflowTargetPicker.file { url in
                        action = .openFile(path: url.path)
                    }
                }
            }

        case .openURL(let url):
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "https://example.com",
                    text: Binding(
                        get: { url },
                        set: { action = .openURL($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                if URL(string: url)?.host?.isEmpty != false {
                    Label("전체 웹사이트 주소를 입력하세요. 예: https://example.com", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

        case .copyTemplate(let templateID, let mode):
            VStack(alignment: .leading, spacing: 14) {
                Picker(
                    "템플릿",
                    selection: Binding(
                        get: { templateID },
                        set: { action = .copyTemplate(templateID: $0, mode: mode) }
                    )
                ) {
                    ForEach(templates) { Text($0.name).tag($0.id) }
                }
                Picker(
                    "처리",
                    selection: Binding(
                        get: { mode },
                        set: { action = .copyTemplate(templateID: templateID, mode: $0) }
                    )
                ) {
                    ForEach(TemplateDeliveryMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

        case .applyLayout(let layoutID):
            Picker(
                "레이아웃",
                selection: Binding(
                    get: { layoutID },
                    set: { action = .applyLayout(layoutID: $0) }
                )
            ) {
                ForEach(layouts) { Text($0.name).tag($0.id) }
            }

        case .pressKey(let key):
            Picker(
                "키 입력",
                selection: Binding(
                    get: { key },
                    set: { action = .pressKey($0) }
                )
            ) {
                ForEach(WorkflowKeyPress.allCases, id: \.self) { key in
                    Text(key.title).tag(key)
                }
            }

        case .wait(let seconds):
            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: Binding(
                    get: { seconds },
                    set: { action = .wait(seconds: $0) }
                ), in: 0.1...30, step: 0.1) {
                    Text("대기 시간: \(seconds.formatted(.number.precision(.fractionLength(1))))초")
                }
                Text("파일 첨부나 화면 전환이 끝날 시간을 확보합니다. 0.1초부터 30초까지 설정할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .runWorkflow(let workflowID):
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    "워크플로",
                    selection: Binding(
                        get: { workflowID },
                        set: { action = .runWorkflow(workflowID: $0) }
                    )
                ) {
                    ForEach(referenceCandidates(including: workflowID)) { workflow in
                        Text(workflow.name).tag(workflow.id)
                    }
                }

                if WorkflowDependencyGraph.wouldCreateCycle(
                    from: currentWorkflowID,
                    to: workflowID,
                    in: workflows
                ) {
                    Label("서로 반복 실행되는 연결입니다. 다른 워크플로를 선택하세요.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

        case .pasteImages(let filePaths):
            selectedFilesEditor(filePaths, kind: .image)

        case .pasteFiles(let filePaths):
            selectedFilesEditor(filePaths, kind: .item)
        }
    }

    private func selectedFileSummary(_ filePaths: [String], itemName: String) -> String {
        guard let firstPath = filePaths.first else { return "\(itemName) 선택" }
        let firstName = URL(fileURLWithPath: firstPath).lastPathComponent
        return filePaths.count == 1 ? firstName : "\(firstName) 외 \(filePaths.count - 1)개"
    }

    @ViewBuilder
    private func selectedFilesEditor(_ filePaths: [String], kind: UTType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(filePaths, id: \.self) { path in
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: kind == .image ? "photo" : "doc")
                    .lineLimit(1)
            }

            if filePaths.contains(where: { !FileManager.default.fileExists(atPath: $0) }) {
                Label("이동되거나 삭제된 항목이 있습니다. 다시 선택해 주세요.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button(kind == .image ? "이미지 다시 선택…" : "파일 다시 선택…") {
                guard let paths = chooseReplacementFiles(kind: kind) else { return }
                action = kind == .image
                    ? .pasteImages(filePaths: paths)
                    : .pasteFiles(filePaths: paths)
            }
        }
    }

    private func chooseReplacementFiles(kind: UTType) -> [String]? {
        let panel = NSOpenPanel()
        panel.title = kind == .image ? "붙여넣을 이미지 선택" : "붙여넣을 파일 선택"
        panel.allowedContentTypes = [kind]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return nil }
        let paths = panel.urls.map(\.path)
        return paths.isEmpty ? nil : paths
    }

    private func referenceCandidates(including selectedID: UUID) -> [Workflow] {
        workflows.filter { candidate in
            candidate.id == selectedID || !WorkflowDependencyGraph.wouldCreateCycle(
                from: currentWorkflowID,
                to: candidate.id,
                in: workflows
            )
        }
    }
}

private struct FlowMarker: View {
    @Environment(\.colorScheme) private var colorScheme
    var number: Int
    var endsFlow: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.wikeyInk(in: colorScheme).opacity(0.34))
                .frame(width: 2)
                .padding(.top, 44)

            if endsFlow {
                VStack {
                    Spacer()
                    Circle()
                        .fill(Color.wikeyInk(in: colorScheme))
                        .frame(width: 6, height: 6)
                }
            }

            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.wikeyInk(in: colorScheme))
                .frame(width: 38, height: 38)
                .background(Color.wikeyInk(in: colorScheme).opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: 46)
        .frame(maxHeight: .infinity)
        .accessibilityLabel("\(number)번째 동작")
    }
}

private struct ActionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var action: WorkflowAction

    var body: some View {
        let icon = action.wikeyIcon
        if case .launchApplication(let bundleIdentifier, _) = action,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .padding(6)
                .background(icon.tint.ink(in: colorScheme).opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
        } else {
            WikeyActionIcon(symbol: icon.symbol, tint: icon.tint, size: 36)
        }
    }
}
