import AppKit
import SwiftUI
import WikeyCore

struct WorkspaceSearchView: View {
    private struct Result: Identifiable {
        var id: SidebarSelection
        var name: String
        var detail: String
        var symbol: String
    }

    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: SidebarSelection?
    var open: (SidebarSelection) -> Void

    private var results: [Result] {
        let sections = SidebarSelection.sections.map {
            Result(id: $0, name: $0.title, detail: "보관함", symbol: $0.symbol)
        }
        let workflows = runtime.store.workflows.map {
            Result(id: .workflow($0.id), name: $0.name,
                   detail: $0.shortcut.steps.isEmpty ? "워크플로" : "워크플로 · \($0.shortcut.displayName)",
                   symbol: "bolt")
        }
        let apps = runtime.store.applicationShortcuts.map {
            Result(id: .application($0.bundleIdentifier), name: $0.displayName,
                   detail: "앱 · \($0.shortcut.displayName)", symbol: "app")
        }
        let templates = runtime.store.templates.map {
            Result(id: .template($0.id), name: $0.name, detail: "템플릿", symbol: "doc.on.clipboard")
        }
        let layouts = runtime.store.layouts.map {
            Result(id: .layout($0.id), name: $0.name,
                   detail: $0.shortcut.steps.isEmpty ? "레이아웃" : "레이아웃 · \($0.shortcut.displayName)",
                   symbol: "rectangle.3.group")
        }
        let allResults = sections + workflows + apps + templates + layouts
        let terms = query.split(whereSeparator: \.isWhitespace)
        return allResults.filter { result in
            terms.allSatisfy { term in
                result.name.localizedCaseInsensitiveContains(String(term))
                    || result.detail.localizedCaseInsensitiveContains(String(term))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                WorkspaceSearchField(
                    text: $query,
                    onMove: moveSelection,
                    onSubmit: openSelected
                )
                .frame(height: 28)
                Button("닫기", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(WikeyPastelButtonStyle(tint: .neutral, iconOnly: true))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                resultList(results)
            }

            Divider()
            HStack {
                Text("↑ ↓ 이동").foregroundStyle(.secondary)
                Text("↵ 열기").foregroundStyle(.secondary)
                Spacer()
                Button("열기", action: openSelected)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 560, height: 390)
        .onChange(of: results.map(\.id), initial: true) { _, ids in
            if selected.map(ids.contains) != true { selected = ids.first }
        }
    }

    private func resultList(_ entries: [Result]) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        Button { open(entry.id) } label: {
                            HStack(spacing: 10) {
                                Label(entry.name, systemImage: entry.symbol)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
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

    private func moveSelection(_ offset: Int) {
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return }
        guard let selected, let index = ids.firstIndex(of: selected) else {
            self.selected = ids.first
            return
        }
        self.selected = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func openSelected() {
        guard let destination = selected, results.contains(where: { $0.id == destination }) else { return }
        open(destination)
    }
}


// Consume navigation commands at the field editor, where macOS handles arrows
// and Return before they reach SwiftUI. Keep the search state in the parent.
private struct WorkspaceSearchField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = AutofocusingSearchField()
        field.placeholderString = "워크플로·앱 단축키·템플릿·레이아웃 찾기"
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
                window.makeFirstResponder(self)
            }
        }
    }
}
