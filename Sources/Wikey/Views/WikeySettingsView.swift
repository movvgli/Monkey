import SwiftUI
import WikeyCore

struct WikeySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.wikeyTheme) private var theme
    @Environment(WikeyRuntime.self) private var runtime
    @Environment(UpdateController.self) private var updates
    @AppStorage(MonkeyMenuBarIcon.visibilityKey) private var showsMenuBarIcon = true
    @AppStorage(MonkeyMenuBarIcon.styleKey) private var menuBarIcon = MonkeyMenuBarIcon.monkey
    @AppStorage(WikeyTheme.storageKey) private var selectedTheme = WikeyTheme.defaultTheme

    private enum Page: String, CaseIterable {
        case general = "일반"
        case permissions = "권한"
        case sync = "동기화"
        case updates = "업데이트"
        case diagnostics = "문제 확인"
    }

    @State private var page: Page = .general

    var body: some View {
        VStack(spacing: 0) {
            WikeyFilterPicker(title: "설정 항목", selection: $page, options: Page.allCases) { page in
                page == .diagnostics && hasErrors ? "문제 확인 •" : page.rawValue
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()

            ScrollView {
                Group {
                    switch page {
                    case .general: general
                    case .permissions: permissions
                    case .sync: ICloudSyncSettingsSection()
                    case .updates: updateSettings
                    case .diagnostics: diagnostics
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 490)
        .background(theme.canvas)
        .task { updates.refresh() }
    }

    private var permissions: some View {
        WikeySection(
            title: "권한",
            detail: "단일 단축키, 앱 실행, 웹사이트 열기와 클립보드 복사는 권한 없이도 사용할 수 있습니다."
        ) {
            if !isRunningFromApplications {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Monkey를 응용 프로그램 폴더에서 실행해 주세요")
                            .font(.headline)
                        Text("macOS 권한은 앱의 설치 위치와 서명을 구분합니다. 위치가 바뀌면 기존 권한이 적용되지 않을 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                }
            }

            PlainPanel {
                VStack(spacing: 0) {
                    PermissionSettingRow(
                        title: "손쉬운 사용",
                        detail: "창 배치·자동 붙여넣기·두 단계 단축키에 사용",
                        granted: runtime.permissions.accessibilityGranted,
                        request: runtime.permissions.requestAccessibility,
                        open: runtime.permissions.openAccessibilitySettings
                    )
                    Divider().padding(.leading, 42)
                    PermissionSettingRow(
                        title: "입력 모니터링",
                        detail: "두 단계 단축키에 사용 · 손쉬운 사용도 필요",
                        granted: runtime.permissions.inputMonitoringGranted,
                        request: runtime.permissions.requestInputMonitoring,
                        open: runtime.permissions.openInputMonitoringSettings
                    )
                }
            }

            if runtime.permissions.inputMonitoringRestartRecommended {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.wikeyInk(in: colorScheme))
                        .font(.title3)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("입력 모니터링을 켰다면 Monkey를 다시 열어 주세요")
                            .font(.headline)
                        Text("macOS는 이 권한을 새로 시작한 앱에 적용합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Monkey 다시 열기") {
                        runtime.permissions.relaunchApplication()
                    }
                }
                .padding(14)
                .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button("권한 상태 새로고침", wikeyIcon: "arrow.clockwise") {
                runtime.permissions.refresh()
            }
            .buttonStyle(WikeyGlossyButtonStyle(tint: .graphite))
        }
    }

    private var general: some View {
        WikeySection(title: "일반") {
            VStack(spacing: 12) {
                PlainPanel {
                    GeneralSettingRow(symbol: "paintpalette", title: "테마") {
                        WikeyFilterPicker(title: "테마", selection: $selectedTheme, options: WikeyTheme.allCases) {
                            $0.title
                        }
                    }
                }

                PlainPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        GeneralSettingRow(symbol: "dock.rectangle", title: "Dock에 Monkey 표시") {
                            generalSwitch(
                                "Dock에 Monkey 표시",
                                isOn: Binding(
                                    get: { runtime.dockIcon.isVisible },
                                    set: { runtime.setDockIconVisible($0) }
                                )
                            )
                        }
                        generalDivider
                        GeneralSettingRow(symbol: "menubar.rectangle", title: "메뉴 막대에 Monkey 표시") {
                            HStack(spacing: 12) {
                                menuBarIconPicker
                                generalSwitch("메뉴 막대에 Monkey 표시", isOn: $showsMenuBarIcon)
                            }
                        }
                        if !showsMenuBarIcon && !runtime.dockIcon.isVisible {
                            Text("Finder의 응용 프로그램에서 Monkey를 다시 열 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, GeneralSettingsLayout.titleInset)
                                .padding(.bottom, 6)
                        }
                    }
                }

                PlainPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        loginSetting
                        generalDivider
                        searchShortcutSetting
                    }
                }
            }
        }
    }

    private var menuBarIconPicker: some View {
        Menu {
            Picker("메뉴 막대 아이콘", selection: $menuBarIcon) {
                ForEach(MonkeyMenuBarIcon.allCases) { icon in
                    Label { Text(icon.title) } icon: { icon.image() }
                        .tag(icon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label { Text(menuBarIcon.title) } icon: { menuBarIcon.image() }
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(theme.accent)
        .accessibilityLabel("메뉴 막대 아이콘")
        .accessibilityValue(menuBarIcon.title)
        .help("메뉴 막대 아이콘")
    }

    private var loginSetting: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingRow(
                symbol: "rectangle.portrait.and.arrow.right",
                title: "로그인 시 Monkey 실행",
                detail: "로그인할 때 단축키를 준비합니다."
            ) {
                generalSwitch(
                    "로그인 시 Monkey 실행",
                    isOn: Binding(
                        get: { runtime.loginItem.isEnabled },
                        set: { runtime.loginItem.setEnabled($0) }
                    )
                )
            }

            if runtime.loginItem.status == .requiresApproval || runtime.loginItem.lastError != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if runtime.loginItem.status == .requiresApproval {
                        Label("macOS 설정에서 로그인 항목을 허용해 주세요.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("로그인 항목 설정 열기") { runtime.loginItem.openSystemSettings() }
                    }
                    if let error = runtime.loginItem.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                    }
                }
                .padding(.leading, GeneralSettingsLayout.titleInset)
                .padding(.bottom, 8)
            }
        }
    }

    private var searchShortcutSetting: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingRow(
                symbol: "magnifyingglass",
                title: "검색창 단축키",
                detail: "다른 앱에서도 검색창을 엽니다."
            ) {
                HStack(spacing: 8) {
                    CompactShortcutRecorderView(shortcut: Binding(
                        get: { runtime.store.searchShortcut },
                        set: {
                            runtime.store.searchShortcut = $0
                            runtime.saveAndReloadHotkeys()
                        }
                    ))
                    Button("기본값") {
                        runtime.store.searchShortcut = .defaultSearch
                        runtime.saveAndReloadHotkeys()
                    }
                    .controlSize(.small)
                    .disabled(runtime.store.searchShortcut == .defaultSearch)
                }
            }
            if let error = runtime.hotkeys.searchRegistrationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                    .padding(.leading, GeneralSettingsLayout.titleInset)
                    .padding(.bottom, 8)
            }
        }
    }

    private func generalSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(WikeyTheme.banana)
    }

    private var generalDivider: some View {
        Divider().padding(.leading, GeneralSettingsLayout.titleInset)
    }

    private var updateSettings: some View {
        WikeySection(
            title: "업데이트",
            detail: "새 버전을 자동으로 확인하고 Monkey 안에서 설치할 수 있습니다."
        ) {
            PlainPanel {
                VStack(spacing: 0) {
                    UpdateSettingRow(
                        title: "자동으로 업데이트 확인",
                        detail: "하루에 한 번 새 버전을 확인합니다.",
                        isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.setAutomaticallyChecksForUpdates($0) }
                        )
                    )

                    Divider().padding(.leading, 42)

                    UpdateSettingRow(
                        title: "업데이트 자동 다운로드",
                        detail: "새 버전을 미리 받아 설치할 준비를 합니다.",
                        isOn: Binding(
                            get: { updates.automaticallyDownloadsUpdates },
                            set: { updates.setAutomaticallyDownloadsUpdates($0) }
                        ),
                        isEnabled: updates.allowsAutomaticUpdates
                    )

                    Divider().padding(.leading, 42)

                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("현재 버전 \(currentVersion)")
                                .font(.headline)
                            Text(lastCheckedText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("지금 확인") {
                            updates.checkForUpdates()
                        }
                        .disabled(!updates.canCheckForUpdates)
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        if hasErrors {
            WikeySection(title: "확인 필요") {
                PlainPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(runtime.hotkeys.registrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.workflows.first(where: { $0.id == id })?.name ?? "워크플로"
                            Label(
                                "\(name): \(runtime.hotkeys.registrationErrors[id] ?? "단축키 오류")",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.hotkeys.layoutRegistrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.layouts.first(where: { $0.id == id })?.name ?? "레이아웃"
                            Label(
                                "\(name): \(runtime.hotkeys.layoutRegistrationErrors[id] ?? "단축키 오류")",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.hotkeys.applicationRegistrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.applicationShortcuts.first(where: { $0.id == id })?.displayName ?? "앱"
                            Label(
                                "\(name): \(runtime.hotkeys.applicationRegistrationErrors[id] ?? "단축키 오류")",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.applicationLaunchErrors.keys), id: \.self) { id in
                            let name = runtime.applicationName(runID: id) ?? "앱"
                            Label(
                                "\(name): \(runtime.applicationLaunchErrors[id] ?? "실행 오류")",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                        }
                        if let error = runtime.store.lastPersistenceError {
                            Label(error, systemImage: "externaldrive.badge.exclamationmark")
                                .foregroundStyle(WikeyActionTint.rose.ink(in: colorScheme))
                        }
                    }
                    .font(.subheadline)
                }
            }
        } else {
            ContentUnavailableView("확인할 문제가 없습니다", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, minHeight: 230)
        }
    }

    private var hasErrors: Bool {
        !runtime.hotkeys.registrationErrors.isEmpty
            || !runtime.hotkeys.layoutRegistrationErrors.isEmpty
            || !runtime.hotkeys.applicationRegistrationErrors.isEmpty
            || !runtime.applicationLaunchErrors.isEmpty
            || runtime.store.lastPersistenceError != nil
    }

    private var isRunningFromApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    private var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        default:
            return "알 수 없음"
        }
    }

    private var lastCheckedText: String {
        guard let date = updates.lastUpdateCheckDate else {
            return "아직 업데이트를 확인하지 않았습니다."
        }
        return "마지막 확인: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private enum GeneralSettingsLayout {
    static let iconWidth: CGFloat = 26
    static let columnSpacing: CGFloat = 12
    static let titleInset = iconWidth + columnSpacing
}

private struct GeneralSettingRow<Control: View>: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: GeneralSettingsLayout.columnSpacing) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: GeneralSettingsLayout.iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control.fixedSize()
        }
        .padding(.vertical, 7)
        .frame(minHeight: 54)
    }
}

private struct UpdateSettingRow: View {
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(WikeyTheme.banana)
                .disabled(!isEnabled)
        }
        .padding(.vertical, 12)
    }
}

private struct PermissionSettingRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var request: () -> Void
    var open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .font(.title3)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(title: granted ? "허용됨" : "꺼짐", tone: granted ? .good : .neutral)
            Button(granted ? "시스템 설정" : "권한 켜기", action: granted ? open : request)
        }
        .padding(.vertical, 12)
    }
}
