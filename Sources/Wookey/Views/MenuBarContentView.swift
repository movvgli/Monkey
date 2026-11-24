import AppKit
import SwiftUI
import WookeyCore

struct MenuBarContentView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(UpdateController.self) private var updates
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    var showSearch: () -> Void

    var body: some View {
        let workflows = runtime.store.workflows.filter { $0.isEnabled && !$0.actions.isEmpty }

        VStack(alignment: .leading, spacing: 5) {
            Text("Wookey")
                .font(.pretendard(.headline))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
            if workflows.isEmpty {
                Text("실행할 워크플로가 없습니다.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 5)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(workflows) { workflow in
                            let icon = workflow.wookeyIcon
                            Button {
                                dismiss()
                                runtime.run(workflowID: workflow.id)
                            } label: {
                                HStack {
                                    rowLabel(shortMenuTitle(workflow.name), symbol: icon.symbol, tint: icon.tint)
                                    if !workflow.shortcut.steps.isEmpty {
                                        ShortcutBadge(text: workflow.shortcut.displayName)
                                    }
                                }
                            }
                            .buttonStyle(WookeyHoverButtonStyle())
                            .disabled(runtime.runner.runningWorkflowID == workflow.id ||
                                      runtime.runner.queuedWorkflowIDs.contains(workflow.id))
                        }
                    }
                }
                .frame(height: min(CGFloat(workflows.count) * 33, 232))
            }

            if !runtime.store.layouts.isEmpty {
                Menu {
                    ForEach(runtime.store.layouts) { layout in
                        Button(shortMenuTitle(layout.name)) {
                            dismiss()
                            runtime.run(layoutID: layout.id)
                        }
                        .disabled(layout.placements.isEmpty ||
                                  runtime.runner.runningWorkflowID == layout.id ||
                                  runtime.runner.queuedWorkflowIDs.contains(layout.id))
                    }
                } label: {
                    rowLabel("레이아웃 적용", symbol: "rectangle.3.group")
                }
                .menuStyle(.borderlessButton)
            }

            if runtime.runner.runningWorkflowID != nil {
                Divider()
                menuButton("실행 중지", symbol: "stop.fill", action: runtime.runner.cancel)
            } else if let lastRun = runtime.lastRun {
                Text(shortMenuTitle(lastRun.menuTitle))
                    .font(.pretendard(.caption))
                    .foregroundStyle(lastRun.failures.isEmpty ? Color.secondary : .orange)
                    .padding(.horizontal, 9)
                    .help(lastRun.failures.first?.message ?? lastRun.workflowName)
            }

            Divider()
            menuButton("Wookey 검색창 열기", symbol: "magnifyingglass") {
                dismiss()
                Task { @MainActor in showSearch() }
            }
            menuButton("Wookey 열기", symbol: "macwindow") {
                dismiss()
                NSApp.unhide(nil)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink {
                rowLabel("설정…", symbol: "gearshape")
            }
            .buttonStyle(WookeyHoverButtonStyle())
            menuButton("업데이트 확인…", symbol: "arrow.clockwise") {
                dismiss()
                updates.checkForUpdates()
            }
            .disabled(!updates.canCheckForUpdates)
            menuButton("Wookey 종료", symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(width: 290)
        .background(theme.panel)
    }

    private func rowLabel(_ title: String, symbol: String, tint: WookeyActionTint? = nil) -> some View {
        HStack(spacing: 8) {
            WookeyActionIcon(symbol: symbol, tint: tint ?? WookeyActionTint(symbol: symbol), size: 16)
            Text(title).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 31)
    }

    private func menuButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, symbol: symbol) }
            .buttonStyle(WookeyHoverButtonStyle())
    }
}
