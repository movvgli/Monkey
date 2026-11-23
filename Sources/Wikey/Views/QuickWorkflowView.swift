import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WikeyCore

struct QuickWorkflowView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case template = "템플릿 사용"
        case link = "링크 열기"
        case app = "앱 열기"
        case file = "파일 열기"

        var id: Self { self }

        var symbol: String {
            switch self {
            case .template: "doc.on.clipboard"
            case .link: "link"
            case .app: "app"
            case .file: "doc"
            }
        }

        var tint: WikeyActionTint {
            switch self {
            case .template: .lavender
            case .link: .periwinkle
            case .app: .mint
            case .file: .peach
            }
        }
    }

    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var kind: Kind?
    @State private var name = ""
    @State private var keyword = ""
    @State private var shortcut = ShortcutGesture()
    @State private var templateID: UUID?
    @State private var templateMode: TemplateDeliveryMode = .copyOnly
    @State private var address = ""
    @State private var application: (id: String, name: String)?
    @State private var file: URL?
    private let initialKind: Kind?
    var onSave: (Workflow) -> Void
    var onAdvanced: () -> Void

    init(initialKind: Kind? = nil, onSave: @escaping (Workflow) -> Void, onAdvanced: @escaping () -> Void) {
        self.initialKind = initialKind
        _kind = State(initialValue: initialKind)
        self.onSave = onSave
        self.onAdvanced = onAdvanced
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind?.rawValue ?? "무엇을 자동화할까요?")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if let kind {
                settings(kind)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(Kind.allCases) { option in
                        Button {
                            kind = option
                        } label: {
                            HStack(spacing: 9) {
                                WikeyActionIcon(symbol: option.symbol, tint: option.tint)
                                Text(option.rawValue)
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 46)
                        }
                        .buttonStyle(WikeyHoverButtonStyle(filled: true))
                    }
                }
            }

            Divider()
            HStack {
                if kind != nil && initialKind == nil {
                    Button("뒤로") { kind = nil }
                } else if kind == nil {
                    Button(action: onAdvanced) {
                        Text("여러 동작 연결…")
                            .foregroundStyle(Color.wikeyInk(in: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(WikeyHoverButtonStyle())
                }
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                if let kind {
                    Button("저장") { save(kind) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(action(kind) == nil || keywordError != nil || (!shortcut.steps.isEmpty && shortcut.validationMessage != nil))
                }
            }
        }
        .padding(24)
        .frame(width: 495)
    }

    private func settings(_ kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            target(kind)

            TextField("이름", text: $name, prompt: Text(defaultName(kind)))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("자동화 이름")

            WorkflowKeywordField(keyword: $keyword)

            VStack(alignment: .leading, spacing: 5) {
                Text("단축키 (선택)")
                    .font(.headline)
                CompactShortcutRecorderView(shortcut: $shortcut)
                if let error = shortcut.validationMessage, !shortcut.steps.isEmpty {
                    Text(error).font(.caption).foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                }
                Text("macOS 단축어 앱에서 ‘Wikey 워크플로 실행’을 추가해 이 자동화를 선택할 수도 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func target(_ kind: Kind) -> some View {
        switch kind {
        case .template:
            if runtime.store.templates.isEmpty {
                Text("템플릿 보관함에서 먼저 템플릿을 만들어 주세요.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("템플릿", selection: $templateID) {
                    Text("템플릿 선택").tag(nil as UUID?)
                    ForEach(runtime.store.templates) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("동작", selection: $templateMode) {
                    ForEach(TemplateDeliveryMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if templateMode == .copyAndPaste {
                    Text("자동으로 붙여넣으려면 손쉬운 사용 권한과 대상 앱의 입력란이 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .link:
            TextField("링크 주소", text: $address, prompt: Text("https://example.com"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("링크 주소")
        case .app:
            Button(application?.name ?? "앱 선택…", systemImage: "app") {
                QuickWorkflowTargetPicker.application { application = $0 }
            }
        case .file:
            Button(file?.lastPathComponent ?? "파일 선택…", systemImage: "doc") {
                QuickWorkflowTargetPicker.file { file = $0 }
            }
        }
    }

    private func action(_ kind: Kind) -> WorkflowAction? {
        switch kind {
        case .template:
            guard let templateID, runtime.store.templates.contains(where: { $0.id == templateID }) else { return nil }
            return .copyTemplate(templateID: templateID, mode: templateMode)
        case .link:
            let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !input.isEmpty else { return nil }
            let value = input.contains("://") ? input : "https://\(input)"
            guard let url = URL(string: value), let host = url.host, !host.isEmpty,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return .openURL(value)
        case .app:
            return application.map { .launchApplication(bundleIdentifier: $0.id, displayName: $0.name) }
        case .file:
            return file.map { .openFile(path: $0.path) }
        }
    }

    private func defaultName(_ kind: Kind) -> String {
        switch kind {
        case .template: runtime.store.templates.first { $0.id == templateID }?.name ?? kind.rawValue
        case .link:
            if case .openURL(let value) = action(kind), let host = URL(string: value)?.host {
                "\(host) 열기"
            } else {
                kind.rawValue
            }
        case .app: application.map { "\($0.name) 열기" } ?? kind.rawValue
        case .file: file.map { "\($0.lastPathComponent) 열기" } ?? kind.rawValue
        }
    }

    private func save(_ kind: Kind) {
        guard let action = action(kind), keywordError == nil else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(Workflow(
            name: title.isEmpty ? defaultName(kind) : title,
            shortcut: shortcut,
            actions: [action],
            keyword: WorkflowKeyword.normalized(keyword)
        ))
    }

    private var keywordError: String? {
        WorkflowKeyword.validationMessage(for: keyword, in: runtime.store.workflows)
    }
}

struct WorkflowKeywordField: View {
    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
    @Binding var keyword: String
    var workflowID: UUID? = nil

    var body: some View {
        let error = WorkflowKeyword.validationMessage(for: keyword, excluding: workflowID, in: runtime.store.workflows)
        VStack(alignment: .leading, spacing: 5) {
            Text("검색 키워드 (선택)").font(.headline)
            TextField("검색 키워드", text: $keyword, prompt: Text("예: gcal"))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("검색 키워드")
            Text(error ?? "검색창에 이 키워드를 입력하면 워크플로를 실행할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(error == nil ? Color.secondary : WikeyActionTint.rose.ink(in: colorScheme))
        }
    }
}

@MainActor
enum QuickWorkflowTargetPicker {
    static func application(_ onSelection: @escaping ((id: String, name: String)) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "열 앱 선택"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            onSelection((identifier, name))
        }
    }

    static func file(_ onSelection: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "열 파일 선택"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { onSelection(url) }
        }
    }
}
