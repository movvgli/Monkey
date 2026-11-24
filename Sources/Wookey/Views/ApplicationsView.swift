import AppKit
import SwiftUI
import WookeyCore

struct ApplicationsView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @State private var applications: [InstalledApplication] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showsAssignedOnly = false

    init(initialSearch: String = "") {
        _searchText = State(initialValue: initialSearch)
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var missingApplications: [ApplicationShortcut] {
        runtime.store.applicationShortcuts.filter { shortcut in
            (searchQuery.isEmpty || shortcut.displayName.localizedCaseInsensitiveContains(searchQuery)
                || shortcut.bundleIdentifier.localizedCaseInsensitiveContains(searchQuery))
                && !applications.contains { $0.bundleIdentifier == shortcut.bundleIdentifier }
                && NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcut.bundleIdentifier) == nil
        }
    }

    private var filteredApplications: [InstalledApplication] {
        let shortcuts = Dictionary(
            runtime.store.applicationShortcuts.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let query = searchQuery
        return applications.filter { application in
            let savedShortcut = shortcuts[application.bundleIdentifier]
            let matchesSearch = query.isEmpty
                || application.displayName.localizedCaseInsensitiveContains(query)
                || application.bundleIdentifier.localizedCaseInsensitiveContains(query)
                || URL(fileURLWithPath: application.path).deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query)
                || savedShortcut?.displayName.localizedCaseInsensitiveContains(query) == true
                || savedShortcut?.shortcut.displayName.localizedCaseInsensitiveContains(query) == true
            let hasShortcut = savedShortcut != nil
            return matchesSearch && (!showsAssignedOnly || hasShortcut)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(WookeyPageMetrics.padding)
                .frame(maxWidth: WookeyPageMetrics.maximumWidth)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.text("설치된 앱을 불러오는 중입니다."))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else if filteredApplications.isEmpty && missingApplications.isEmpty {
                        ContentUnavailableView {
                            WookeyEmptyStateLabel(
                                title: showsAssignedOnly && searchText.isEmpty ? L10n.text("지정된 단축키가 없습니다") : L10n.text("앱을 찾을 수 없습니다"),
                                symbol: SidebarSelection.applications.symbol
                            )
                        } description: {
                            Text(showsAssignedOnly ? L10n.text("‘전체 앱’에서 앱을 선택해 단축키를 지정하세요.") : L10n.text("다른 이름으로 검색하거나 앱 목록을 새로고침해 주세요."))
                        }
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else if !filteredApplications.isEmpty {
                        applicationList(filteredApplications)
                    }

                    if !isLoading && !missingApplications.isEmpty {
                        WookeySection(title: L10n.text("설치 위치를 찾을 수 없는 앱"), detail: L10n.text("앱을 다시 설치하거나 사용하지 않는 단축키를 지워 주세요.")) {
                            PlainPanel {
                                VStack(spacing: 12) {
                                    ForEach(missingApplications) { application in
                                        HStack {
                                            Label(application.displayName, systemImage: "exclamationmark.triangle")
                                                .foregroundStyle(.orange)
                                            Spacer()
                                            ShortcutBadge(text: application.shortcut.displayName)
                                            Button(L10n.text("단축키 삭제")) {
                                                runtime.setApplicationShortcut(
                                                    bundleIdentifier: application.bundleIdentifier,
                                                    displayName: application.displayName,
                                                    shortcut: ShortcutGesture()
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(WookeyPageMetrics.padding)
                .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle(L10n.text("앱"))
        .task {
            await reloadApplications()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WookeyPageMetrics.headerSpacing) {
            WookeyPageHeader(title: L10n.text("앱"), subtitle: L10n.text("설치된 앱에 단축키를 지정하고 바로 실행합니다.")) {
                Button(L10n.text("새로고침"), wookeyIcon: "arrow.clockwise") {
                    Task { await reloadApplications() }
                }
                .buttonStyle(WookeyGlossyButtonStyle())
                .controlSize(.large)
                .disabled(isLoading)
            }

            WookeySearchField(prompt: L10n.text("앱 이름·단축키 검색"), text: $searchText)
            HStack {
                Text(L10n.text("설치된 앱 \(applications.count)개 · 단축키 \(runtime.store.applicationShortcuts.count)개"))
                    .font(.pretendard(.subheadline))
                    .foregroundStyle(.secondary)
                Spacer()
                WookeyFilterPicker(title: L10n.text("앱 필터"), selection: $showsAssignedOnly, options: [false, true]) {
                    $0 ? L10n.text("단축키 지정됨") : L10n.text("전체 앱")
                }
            }
        }
    }

    private func applicationList(_ applications: [InstalledApplication]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(L10n.text("앱"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("단축키"))
                    .frame(width: 228, alignment: .leading)
                Text(L10n.text("실행"))
                    .frame(width: 32)
            }
            .font(.pretendard(.subheadline, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 44)

            Divider()
                .padding(.horizontal, 18)

            LazyVStack(spacing: 0) {
                ForEach(applications) { application in
                    ApplicationShortcutRow(
                        application: application,
                        shortcut: shortcutBinding(for: application),
                        conflictMessage: conflictMessage(for: application),
                        launchError: runtime.applicationLaunchError(bundleIdentifier: application.bundleIdentifier),
                        isRunning: isRunning(application),
                        run: {
                            runtime.runApplication(
                                bundleIdentifier: application.bundleIdentifier,
                                displayName: application.displayName
                            )
                        }
                    )
                    if application.id != applications.last?.id {
                        Divider()
                            .padding(.leading, 66)
                    }
                }
            }
        }
        .background(
            theme.panel,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }

    private func shortcutBinding(for application: InstalledApplication) -> Binding<ShortcutGesture> {
        Binding(
            get: {
                runtime.store.applicationShortcuts.first(where: {
                    $0.bundleIdentifier == application.bundleIdentifier
                })?.shortcut ?? ShortcutGesture()
            },
            set: { shortcut in
                runtime.setApplicationShortcut(
                    bundleIdentifier: application.bundleIdentifier,
                    displayName: application.displayName,
                    shortcut: shortcut
                )
            }
        )
    }

    private func conflictMessage(for application: InstalledApplication) -> String? {
        guard let shortcut = runtime.store.applicationShortcuts.first(where: {
            $0.bundleIdentifier == application.bundleIdentifier
        }) else { return nil }
        return runtime.hotkeys.applicationRegistrationErrors[shortcut.id]
    }

    private func reloadApplications() async {
        isLoading = true
        applications = await InstalledApplicationCatalog.load()
        isLoading = false
    }

    private func isRunning(_ application: InstalledApplication) -> Bool {
        guard let id = runtime.applicationRunID(bundleIdentifier: application.bundleIdentifier) else { return false }
        return runtime.runner.runningWorkflowID == id || runtime.runner.queuedWorkflowIDs.contains(id)
    }
}

private struct ApplicationShortcutRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var application: InstalledApplication
    @Binding var shortcut: ShortcutGesture
    var conflictMessage: String?
    var launchError: String?
    var isRunning: Bool
    var run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: application.path))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.pretendard(size: 15, weight: .medium))
                        .lineLimit(1)
                    if conflictMessage != nil {
                        Text(L10n.text("단축키 확인 필요"))
                            .font(.pretendard(.caption))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CompactShortcutRecorderView(shortcut: $shortcut)
                    .frame(width: 228, alignment: .leading)
                Button(action: run) {
                    Group {
                        if isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            WookeyActionIcon(symbol: "play.fill", tint: .accent, size: 14)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                .disabled(isRunning)
                .foregroundStyle(Color.wookeyInk(in: colorScheme))
                .help(L10n.text("\(application.displayName) 열기"))
                .accessibilityLabel(L10n.text("\(application.displayName) 열기"))
            }
            if let launchError {
                Label(launchError, systemImage: "exclamationmark.triangle.fill")
                    .font(.pretendard(.caption))
                    .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                    .padding(.leading, 48)
            }

            if let conflictMessage {
                Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.pretendard(.caption))
                    .foregroundStyle(.orange)
                    .padding(.leading, 48)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, conflictMessage == nil ? 12 : 9)
    }
}
