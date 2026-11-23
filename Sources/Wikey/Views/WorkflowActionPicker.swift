import SwiftUI

struct WorkflowActionPicker: View {
    enum Group: String, CaseIterable {
        case open = "열기 및 실행"
        case paste = "붙여넣기"
        case input = "키 입력 및 대기"

        var options: [Option] {
            switch self {
            case .open: [.app, .website, .file, .layout, .workflow]
            case .paste: [.template, .images, .files]
            case .input: [.enter, .shiftEnter, .wait]
            }
        }
    }

    enum Option: String {
        case app = "앱 열기"
        case website = "링크 열기"
        case file = "파일 열기"
        case layout = "창 레이아웃 적용"
        case workflow = "다른 워크플로 실행"
        case template = "템플릿 붙여넣기"
        case images = "이미지 붙여넣기"
        case files = "파일 붙여넣기"
        case enter = "Enter 입력"
        case shiftEnter = "Shift + Enter 입력"
        case wait = "잠시 기다리기"

        var icon: (symbol: String, tint: WikeyActionTint) {
            switch self {
            case .app: ("app", .accent)
            case .website: ("link", .graphite)
            case .file: ("doc", .graphite)
            case .layout: ("rectangle.3.group", .accent)
            case .workflow: ("bolt", .accent)
            case .template: ("doc.on.clipboard", .accent)
            case .images: ("photo", .graphite)
            case .files: ("paperclip", .graphite)
            case .enter: ("return", .neutral)
            case .shiftEnter: ("arrow.turn.down.left", .neutral)
            case .wait: ("clock", .neutral)
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selected: Option?
    var templatesAvailable: Bool
    var layoutsAvailable: Bool
    var workflowsAvailable: Bool
    var choose: (Option) -> Void

    private func filteredOptions(_ group: Group) -> [Option] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return group.options.filter { search.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(search) }
    }

    private func unavailableReason(_ option: Option) -> String? {
        switch option {
        case .template where !templatesAvailable: "템플릿 보관함에서 먼저 만들어 주세요"
        case .layout where !layoutsAvailable: "레이아웃 보관함에서 먼저 만들어 주세요"
        case .workflow where !workflowsAvailable: "연결할 수 있는 다른 워크플로가 없습니다"
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("동작 추가").font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("동작 검색", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($searchFocused)
                        .onSubmit(addSelection)
                }
            }
            .padding(18)
            Divider()

            if Group.allCases.allSatisfy({ filteredOptions($0).isEmpty }) {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selected) {
                    ForEach(Group.allCases, id: \.self) { group in
                        if !filteredOptions(group).isEmpty {
                            Section(group.rawValue) {
                                ForEach(filteredOptions(group), id: \.self) { option in
                                    HStack(spacing: 9) {
                                        WikeyActionIcon(symbol: option.icon.symbol, tint: option.icon.tint)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.rawValue)
                                            if let reason = unavailableReason(option) {
                                                Text(reason)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 3)
                                    .tag(option)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .buttonStyle(WikeyGlossyButtonStyle(tint: .neutral))
                    .keyboardShortcut(.cancelAction)
                Button("선택", action: addSelection)
                    .buttonStyle(WikeyGlossyButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || selected.flatMap(unavailableReason) != nil)
            }
            .padding(16)
        }
        .frame(width: 490, height: 540)
        .onAppear {
            searchFocused = true
            selectFirstAvailable()
        }
        .onChange(of: query) { selectFirstAvailable() }
    }

    private func selectFirstAvailable() {
        selected = Group.allCases.flatMap(filteredOptions).first { unavailableReason($0) == nil }
    }

    private func addSelection() {
        guard let selected, unavailableReason(selected) == nil,
              Group.allCases.flatMap(filteredOptions).contains(selected) else { return }
        choose(selected)
    }
}

struct WorkflowActionSetupSheet<Content: View>: View {
    var title: String
    var canAdd: Bool
    var cancel: () -> Void
    var add: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            content
            HStack {
                Spacer()
                Button("취소", action: cancel)
                    .buttonStyle(WikeyGlossyButtonStyle(tint: .neutral))
                    .keyboardShortcut(.cancelAction)
                Button("동작 추가", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(WikeyGlossyButtonStyle())
                    .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}
