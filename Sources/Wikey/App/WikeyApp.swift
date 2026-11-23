import AppKit
import SwiftUI
import WikeyCore

extension Color {
    static let wikeyAccent = Color(white: 0.26)

    static func wikeyInk(in colorScheme: ColorScheme) -> Color {
        Color(white: colorScheme == .dark ? 0.9 : 0.15)
    }
}

@main
struct WikeyApp: App {
    @NSApplicationDelegateAdaptor(WikeyAppDelegate.self) private var appDelegate
    @AppStorage(MonkeyMenuBarIcon.visibilityKey) private var showsMenuBarIcon = true
    @AppStorage(MonkeyMenuBarIcon.styleKey) private var menuBarIcon = MonkeyMenuBarIcon.monkey
    @State private var runtime = WikeyAppRuntime.shared
    @State private var updates = UpdateController()

    var body: some Scene {
        Window("Monkey", id: "main") {
            ContentView()
                .environment(runtime)
                .environment(updates)
                .tint(.wikeyAccent)
                .accentColor(.wikeyAccent)
                .task { runtime.start() }
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
            }

            WorkspaceCommands()

            CommandMenu("워크플로") {
                ForEach(runtime.store.workflows.filter(\.isEnabled)) { workflow in
                    Button(shortMenuTitle(workflow.name)) {
                        runtime.run(workflowID: workflow.id)
                    }
                }
            }
        }

        MenuBarExtra(isInserted: $showsMenuBarIcon) {
            MenuBarContentView(showSearch: appDelegate.toggleSearch)
                .environment(runtime)
                .environment(updates)
                .tint(.wikeyAccent)
                .task { runtime.start() }
        } label: {
            Label {
                Text(menuBarActivity?.label ?? "Monkey")
            } icon: {
                menuBarIcon.image(activity: menuBarActivity)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            WikeySettingsView()
                .environment(runtime)
                .environment(updates)
                .tint(.wikeyAccent)
                .accentColor(.wikeyAccent)
        }
    }

    private var menuBarActivity: MonkeyMenuBarIcon.Activity? {
        if runtime.lastRun?.failures.isEmpty == false { return .failed }
        if runtime.runner.runningWorkflowID != nil { return .running }
        return nil
    }
}

@MainActor
enum WikeyAppRuntime {
    static let shared: WikeyRuntime = {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--test-store"),
           arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/") {
            return WikeyRuntime(storeRootURL: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
        }
        return WikeyRuntime()
    }()

    static func start() -> WikeyRuntime {
        shared.start()
        return shared
    }
}

struct WorkspaceActions {
    var createWorkflow: () -> Void
    var search: () -> Void
}

private struct WorkspaceActionsKey: FocusedValueKey {
    typealias Value = WorkspaceActions
}

extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}

private struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("새 워크플로") { actions?.createWorkflow() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Monkey 검색…") { actions?.search() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}

@MainActor
final class WikeyAppDelegate: NSObject, NSApplicationDelegate {
    private lazy var searchPanel = WorkspaceSearchPanel(runtime: WikeyAppRuntime.shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Monkey menu bar runtime")
        let activationPolicy = DockIconService.activationPolicy(for: DockIconService.savedVisibility())
        if NSApp.activationPolicy() != activationPolicy {
            NSApp.setActivationPolicy(activationPolicy)
        }
        let runtime = WikeyAppRuntime.shared
        runtime.hotkeys.onSearch = { [weak self] in self?.toggleSearch() }
        runtime.start()
        if ProcessInfo.processInfo.arguments.contains("--background") {
            DispatchQueue.main.async {
                // Keep the app available to the launcher while leaving its main window out of view.
                for window in NSApp.windows where window.canBecomeMain { window.orderOut(nil) }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func toggleSearch() {
        searchPanel.toggle()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

func shortMenuTitle(_ title: String) -> String {
    title.count <= 30 ? title : String(title.prefix(27)) + "..."
}
