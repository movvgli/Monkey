import SwiftUI
import WookeyCore

struct TemplateEditorView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme
    @Binding var template: RichTemplate
    var onBack: () -> Void
    var onDelete: () -> Void
    @State private var editor = RichTextEditorController()
    @State private var copyState: CopyState = .idle
    @State private var showsDeleteConfirmation = false
    @State private var copyError: String?

    private enum CopyState {
        case idle
        case copied
        case failed
    }

    var body: some View {
        VStack(spacing: 0) {
            WookeyEditorHeader(
                title: $template.name,
                subtitle: "서식과 이미지를 그대로 보관합니다. 내용은 자동으로 저장됩니다.",
                onBack: onBack
            ) {
                if copyState != .idle {
                    Label(
                        copyState == .copied ? "복사됨" : "복사 실패",
                        systemImage: copyState == .copied ? "checkmark" : "exclamationmark.triangle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(copyState == .copied ? Color.green : Color.orange)
                    .transition(.opacity)
                }
                WookeyDeleteButton(title: "템플릿 삭제") {
                    showsDeleteConfirmation = true
                }
                Button("클립보드에 복사", wookeyIcon: "doc.on.doc", action: copyTemplate)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
            }

            Divider()

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    toolButton("굵게", symbol: "bold", action: editor.toggleBold)
                    toolButton("기울임", symbol: "italic", action: editor.toggleItalic)
                    toolButton("밑줄", symbol: "underline", action: editor.toggleUnderline)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("글자 서식")

                Divider().frame(height: 22)

                HStack(spacing: 5) {
                    toolButton("링크 추가", symbol: "link", tint: .graphite, action: editor.addLink)
                    toolButton("목록 항목 추가", symbol: "list.bullet", tint: .accent, action: editor.insertBullet)
                    toolButton("이미지 넣기", symbol: "photo", tint: .graphite, action: editor.insertImage)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("삽입")
                Spacer()
                WookeySaveStatus()
            }
            .padding(.horizontal, WookeyPageMetrics.padding)
            .padding(.vertical, 10)
            .background(theme.panel)

            Divider()

            if let copyError {
                Label(copyError, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            ZStack {
                theme.canvas
                RichTextEditor(controller: editor)
                    .frame(maxWidth: 760)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.quaternary)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
        }
        .navigationTitle(template.name)
        .task(id: template.id) {
            let templateID = template.id
            let store = runtime.store
            editor.load(store.templateDocument(id: templateID))
            editor.onDocumentChange = { [weak store] document in
                store?.saveTemplateDocument(document, for: templateID)
            }
        }
        .alert("템플릿을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive, action: onDelete)
        } message: {
            Text("‘\(template.name)’과 이 템플릿을 사용하는 워크플로 동작이 함께 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    private func toolButton(
        _ title: String,
        symbol: String,
        tint: WookeyActionTint = .accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            WookeyActionIcon(symbol: symbol, tint: tint, size: 15)
        }
        .buttonStyle(WookeyGlossyButtonStyle(tint: tint, iconOnly: true))
        .accessibilityLabel(title)
        .help(title)
    }

    private func copyTemplate() {
        do {
            try runtime.clipboard.copy(runtime.store.templateDocument(id: template.id))
            copyError = nil
            showCopyState(.copied)
        } catch {
            copyError = error.localizedDescription
            showCopyState(.failed)
        }
    }

    private func showCopyState(_ state: CopyState) {
        withAnimation(.easeOut(duration: 0.15)) {
            copyState = state
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeIn(duration: 0.15)) {
                copyState = .idle
            }
        }
    }
}
