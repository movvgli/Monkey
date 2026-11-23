import AppKit
import SwiftUI
import WookeyCore

struct NewTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WookeyRuntime.self) private var runtime
    @State private var editor = RichTextEditorController()
    @State private var name = ""
    @State private var document = NSAttributedString()
    @State private var editingText = ""
    @State private var saveError: String?
    let onCreated: (UUID) -> Void

    private var hasContent: Bool {
        !document.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                WookeyActionIcon(symbol: wookeyTemplateSymbol, tint: .amber, size: 26)
                Text("새 템플릿").font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("이름").font(.subheadline.weight(.semibold))
                TextField("비워두면 내용의 첫 줄을 사용합니다", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .accessibilityLabel("템플릿 이름")
            }

            TemplateContentField(
                editor: editor,
                isEmpty: editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                focusesOnAppear: true
            )

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    WookeyControlLabel(title: "템플릿 저장", symbol: "checkmark.circle.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(WookeyHoverButtonStyle(selected: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!hasContent)
            }
        }
        .padding(24)
        .frame(width: 570, height: 490)
        .onAppear {
            editor.onDocumentChange = { document = $0 }
            editor.onTextChange = { editingText = $0 }
        }
        .onDisappear {
            editor.onDocumentChange = nil
            editor.onTextChange = nil
        }
    }

    private func save() {
        guard hasContent, editor.textView?.hasMarkedText() != true else { return }
        let customName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = document.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let savedName = customName.isEmpty ? firstLine.map { String($0.prefix(36)) } ?? "이미지 템플릿" : customName
        guard let id = runtime.store.addTemplate(name: savedName, document: document) else {
            saveError = runtime.store.lastPersistenceError ?? "템플릿을 저장하지 못했습니다."
            return
        }
        onCreated(id)
    }
}

struct TemplateEditorView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
    @Binding var template: RichTemplate
    var onBack: () -> Void
    var onDelete: () -> Void
    @State private var editor = RichTextEditorController()
    @State private var autosaver = TemplateDocumentAutosaver()
    @State private var editingText: String?
    @State private var didCopy = false
    @State private var showsDeleteConfirmation = false
    @State private var copyError: String?

    var body: some View {
        VStack(spacing: 0) {
            WookeyEditorHeader(title: $template.name, subtitle: "내용을 수정하면 자동으로 저장됩니다.", onBack: onBack) {
                WookeyDeleteButton(title: "템플릿 삭제") { showsDeleteConfirmation = true }
            }

            Divider()

            TemplateContentField(editor: editor, isEmpty: (editingText ?? template.plainText).isEmpty)
                .frame(maxWidth: 760)
                .padding(WookeyPageMetrics.padding)
                .frame(maxWidth: .infinity)

            Divider()

            HStack(spacing: 10) {
                WookeySaveStatus()
                if let copyError {
                    Label(copyError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                }
                Spacer()
                Button(didCopy ? "복사됨" : "복사", wookeyIcon: didCopy ? "checkmark.circle.fill" : "doc.on.doc", action: copyTemplate)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
                    .help("템플릿 내용을 클립보드에 복사")
            }
            .padding(.horizontal, WookeyPageMetrics.padding)
            .padding(.vertical, 11)
            .background(theme.panel)
        }
        .navigationTitle(template.name)
        .task(id: template.id) {
            let id = template.id
            let store = runtime.store
            editor.commitMarkedText()
            autosaver.flush()
            editingText = nil
            editor.load(store.templateDocument(id: id))
            editor.onDocumentChange = { [weak store, autosaver] document in
                guard let store else { return }
                autosaver.schedule(document, for: id, in: store)
            }
            editor.onTextChange = { editingText = $0 }
        }
        .onDisappear {
            editor.commitMarkedText()
            autosaver.flush()
            editor.onDocumentChange = nil
            editor.onTextChange = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            editor.commitMarkedText()
            autosaver.flush()
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { didCopy = false }
        }
        .alert("템플릿을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive, action: onDelete)
        } message: {
            Text("‘\(template.name)’과 이 템플릿을 사용하는 워크플로 동작이 함께 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    private func copyTemplate() {
        editor.commitMarkedText()
        autosaver.flush()
        do {
            try runtime.clipboard.copy(runtime.store.templateDocument(id: template.id))
            copyError = nil
            didCopy = true
        } catch {
            didCopy = false
            copyError = error.localizedDescription
        }
    }
}

/// Coalesces template edits so typing doesn't encode RTFD and write to disk on every keystroke.
@MainActor
private final class TemplateDocumentAutosaver {
    private var pending: (id: UUID, document: NSAttributedString, store: WookeyStore)?
    private var saveTask: Task<Void, Never>?

    func schedule(_ document: NSAttributedString, for id: UUID, in store: WookeyStore) {
        pending = (id, document, store)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let pending else { return }
        self.pending = nil
        pending.store.saveTemplateDocument(pending.document, for: pending.id)
    }
}

private struct TemplateContentField: View {
    @Environment(\.wookeyTheme) private var theme
    @State private var showsFormatting = false
    let editor: RichTextEditorController
    let isEmpty: Bool
    var focusesOnAppear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("내용").font(.subheadline.weight(.semibold))
                Spacer()
                Button("서식", wookeyIcon: "slider.horizontal.3") { showsFormatting.toggle() }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .accessibilityValue(showsFormatting ? "펼쳐짐" : "접힘")
                Button("이미지 추가", wookeyIcon: "photo", action: editor.insertImage)
                    .buttonStyle(WookeyGlossyButtonStyle())
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showsFormatting {
                Divider()
                HStack(spacing: 5) {
                    formatButton("굵게", symbol: "bold", action: editor.toggleBold)
                    formatButton("기울임", symbol: "italic", action: editor.toggleItalic)
                    formatButton("밑줄", symbol: "underline", action: editor.toggleUnderline)
                    Divider().frame(height: 17).padding(.horizontal, 3)
                    formatButton("목록 항목 추가", symbol: "list.bullet", action: editor.insertBullet)
                    formatButton("링크 추가", symbol: "link", action: editor.addLink)
                    Spacer()
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("글자 서식")
            }

            Divider()

            ZStack(alignment: .topLeading) {
                RichTextEditor(controller: editor, focusesOnAppear: focusesOnAppear)
                if isEmpty {
                    Text("자주 쓰는 내용을 입력하거나 붙여넣으세요.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 27)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint("내용을 입력하거나 붙여넣으세요.")
        }
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
    }

    private func formatButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, wookeyIcon: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
            .accessibilityLabel(title)
            .help(title)
    }
}
