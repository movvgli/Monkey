import SwiftUI
import WookeyCore

struct WorkflowReferenceSetupView: View {
    @Environment(\.wookeyTheme) private var theme
    var workflows: [Workflow]
    @Binding var selectedWorkflowID: UUID?
    var onCancel: () -> Void
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("다른 워크플로 실행 추가"))
                    .font(.title2.weight(.semibold))
                Text(L10n.text("이 위치에서 이어서 실행할 워크플로를 선택하세요."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(workflows) { workflow in
                        workflowButton(workflow)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 10) {
                Text(L10n.text("선택한 워크플로의 동작이 이 순서에서 실행됩니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("취소"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("동작 추가"), action: onAdd)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedWorkflowID == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(theme.panel)
        }
        .frame(width: 520, height: 420)
    }

    private func workflowButton(_ workflow: Workflow) -> some View {
        WookeySelectionCard(
            title: workflow.name,
            subtitle: L10n.text("동작 \(workflow.actions.count)개"),
            symbol: "bolt",
            tint: .accent,
            isSelected: selectedWorkflowID == workflow.id,
            accessibilityLabel: L10n.text("\(workflow.name) 워크플로")
        ) {
            selectedWorkflowID = workflow.id
        } accessory: {
            if !workflow.shortcut.steps.isEmpty {
                ShortcutBadge(text: workflow.shortcut.displayName)
            }
        }
    }
}
