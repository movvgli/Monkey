import SwiftUI
import WookeyCore

struct WookeySettingsView: View {
    static let windowSize = CGSize(width: 720, height: 490)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(UpdateController.self) private var updates
    @AppStorage(WookeyMenuBarIcon.visibilityKey) private var showsMenuBarIcon = true
    @AppStorage(WookeyMenuBarIcon.styleKey) private var menuBarIcon = WookeyMenuBarIcon.character
    @AppStorage(WookeyCharacter.storageKey) private var character = WookeyCharacter.wookey
    @AppStorage(WookeyIconTheme.storageKey) private var iconTheme = WookeyIconTheme.threeDimensional
    @AppStorage(WookeyTheme.storageKey) private var selectedTheme = WookeyTheme.defaultTheme
    @AppStorage(SearchWebAddress.Engine.storageKey) private var webSearchEngine = SearchWebAddress.Engine.google
    @AppStorage(ShelfAfterDrop.storageKey) private var shelfAfterDrop = ShelfAfterDrop.defaultValue

    private enum Page: String, CaseIterable {
        case general = "일반"
        case permissions = "권한"
        case history = "보관 기간"
        case sync = "동기화"
        case updates = "업데이트"
        case diagnostics = "문제 확인"

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .permissions: "lock.shield"
            case .history: "clock"
            case .sync: "icloud"
            case .updates: "arrow.clockwise"
            case .diagnostics: "stethoscope"
            }
        }
    }

    @State private var page: Page = .general

    var body: some View {
        VStack(spacing: 0) {
            WookeyFilterPicker(title: L10n.text("설정 항목"), selection: $page, options: Page.allCases, icon: { $0.symbol }) { page in
                page == .diagnostics && hasErrors ? L10n.text("문제 확인 •") : L10n.label(page.rawValue)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()

            ScrollView {
                Group {
                    switch page {
                    case .general: general
                    case .permissions: permissions
                    case .history: HistorySettingsView()
                    case .sync: ICloudSyncSettingsSection()
                    case .updates: updateSettings
                    case .diagnostics: diagnostics
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background(theme.canvas)
        .onChange(of: iconTheme) { _, theme in theme.applyDockIcon() }
        .onChange(of: runtime.dockIcon.isVisible) { _, isVisible in
            if isVisible { iconTheme.applyDockIcon() }
        }
        .task { updates.refresh() }
    }

    private var permissions: some View {
        WookeySection(
            title: L10n.text("권한"),
            detail: L10n.text("단일 단축키, 앱 실행, 웹사이트 열기와 클립보드 복사는 권한 없이도 사용할 수 있습니다.")
        ) {
            if !isRunningFromApplications {
                HStack(alignment: .top, spacing: 10) {
                    WookeyActionIcon(symbol: "info.circle.fill", tint: .accent, size: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Wookey를 응용 프로그램 폴더에서 실행해 주세요"))
                            .font(.headline)
                        Text(L10n.text("macOS 권한은 앱의 설치 위치와 서명을 구분합니다. 위치가 바뀌면 기존 권한이 적용되지 않을 수 있습니다."))
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
                        symbol: "accessibility",
                        title: L10n.text("손쉬운 사용"),
                        detail: L10n.text("창 배치·자동 붙여넣기·두 단계 단축키에 사용"),
                        granted: runtime.permissions.accessibilityGranted,
                        request: runtime.permissions.requestAccessibility,
                        open: runtime.permissions.openAccessibilitySettings
                    )
                    Divider().padding(.leading, 42)
                    PermissionSettingRow(
                        symbol: "keyboard",
                        title: L10n.text("입력 모니터링"),
                        detail: L10n.text("두 단계 단축키에 사용 · 손쉬운 사용도 필요"),
                        granted: runtime.permissions.inputMonitoringGranted,
                        request: runtime.permissions.requestInputMonitoring,
                        open: runtime.permissions.openInputMonitoringSettings
                    )
                }
            }

            if runtime.permissions.inputMonitoringRestartRecommended {
                HStack(spacing: 12) {
                    WookeyActionIcon(symbol: "arrow.clockwise.circle.fill", tint: .accent, size: 20)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("입력 모니터링을 켰다면 Wookey를 다시 열어 주세요"))
                            .font(.headline)
                        Text(L10n.text("macOS는 이 권한을 새로 시작한 앱에 적용합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text("Wookey 다시 열기")) {
                        runtime.permissions.relaunchApplication()
                    }
                }
                .padding(14)
                .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(L10n.text("권한 상태 새로고침"), wookeyIcon: "arrow.clockwise") {
                runtime.permissions.refresh()
            }
            .buttonStyle(WookeyGlossyButtonStyle())
        }
    }

    private var general: some View {
        WookeySection(title: L10n.text("일반")) {
            VStack(spacing: 12) {
                PlainPanel {
                    GeneralSettingRow(symbol: "paintpalette", title: L10n.text("테마")) {
                        WookeyFilterPicker(title: L10n.text("테마"), selection: $selectedTheme, options: WookeyTheme.allCases) {
                            $0.title
                        }
                    }
                }

                PlainPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        GeneralSettingRow(symbol: "face.smiling", title: L10n.text("캐릭터")) {
                            WookeyFilterPicker(title: L10n.text("캐릭터"), selection: $character, options: WookeyCharacter.allCases) {
                                $0.title
                            }
                        }
                        generalDivider
                        GeneralSettingRow(symbol: "square.stack.3d.up", title: L10n.text("아이콘 테마")) {
                            WookeyFilterPicker(title: L10n.text("아이콘 테마"), selection: $iconTheme, options: WookeyIconTheme.allCases) {
                                $0.title
                            }
                        }
                        if artworkIsPending {
                            Text(L10n.text("아직 추가되지 않은 그림은 기존 아이콘으로 표시됩니다."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, GeneralSettingsLayout.titleInset)
                                .padding(.bottom, 6)
                        }
                    }
                }

                PlainPanel {
                    GeneralSettingRow(symbol: HistoryKind.files.symbol, title: L10n.text("파일을 담은 뒤 우키 서랍")) {
                        WookeyFilterPicker(title: L10n.text("파일을 담은 뒤 우키 서랍"), selection: $shelfAfterDrop, options: ShelfAfterDrop.allCases) {
                            $0.title
                        }
                    }
                }

                PlainPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        GeneralSettingRow(symbol: "dock.rectangle", title: L10n.text("Dock에 Wookey 표시")) {
                            generalSwitch(
                                L10n.text("Dock에 Wookey 표시"),
                                isOn: Binding(
                                    get: { runtime.dockIcon.isVisible },
                                    set: { runtime.setDockIconVisible($0) }
                                )
                            )
                        }
                        generalDivider
                        GeneralSettingRow(symbol: "menubar.rectangle", title: L10n.text("메뉴 막대에 Wookey 표시")) {
                            HStack(spacing: 12) {
                                menuBarIconPicker
                                generalSwitch(L10n.text("메뉴 막대에 Wookey 표시"), isOn: $showsMenuBarIcon)
                            }
                        }
                        if !showsMenuBarIcon && !runtime.dockIcon.isVisible {
                            Text(L10n.text("Finder의 응용 프로그램에서 Wookey를 다시 열 수 있습니다."))
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
                        generalDivider
                        webSearchEngineSetting
                    }
                }
            }
        }
    }

    private var artworkIsPending: Bool {
        let characterArtwork = [character.shelfArtwork, character.companionArtwork]
            + WookeyMenuBarIcon.allCases.map { $0.artwork(for: character) }
        return characterArtwork.contains { !iconTheme.hasArtwork($0) }
            || (iconTheme == .fluffy && !iconTheme.hasArtwork("WookeyCommandSettings"))
    }

    private var menuBarIconPicker: some View {
        Menu {
            Picker(L10n.text("메뉴 막대 아이콘"), selection: $menuBarIcon) {
                ForEach(WookeyMenuBarIcon.allCases) { icon in
                    Label { Text(icon.title(for: character)) } icon: { icon.image(character: character, theme: iconTheme) }
                        .tag(icon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label { Text(menuBarIcon.title(for: character)) } icon: { menuBarIcon.image(character: character, theme: iconTheme) }
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(theme.accent)
        .accessibilityLabel(L10n.text("메뉴 막대 아이콘"))
        .accessibilityValue(menuBarIcon.title(for: character))
        .help(L10n.text("메뉴 막대 아이콘"))
    }

    private var loginSetting: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingRow(
                symbol: "door.left.hand.open",
                title: L10n.text("로그인 시 Wookey 실행"),
                detail: L10n.text("로그인할 때 단축키를 준비합니다.")
            ) {
                generalSwitch(
                    L10n.text("로그인 시 Wookey 실행"),
                    isOn: Binding(
                        get: { runtime.loginItem.isEnabled },
                        set: { runtime.loginItem.setEnabled($0) }
                    )
                )
            }

            if runtime.loginItem.status == .requiresApproval || runtime.loginItem.lastError != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if runtime.loginItem.status == .requiresApproval {
                        WookeyControlLabel(title: L10n.text("macOS 설정에서 로그인 항목을 허용해 주세요."), symbol: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.text("로그인 항목 설정 열기")) { runtime.loginItem.openSystemSettings() }
                    }
                    if let error = runtime.loginItem.lastError {
                        WookeyControlLabel(title: error, symbol: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                    }
                }
                .padding(.leading, GeneralSettingsLayout.titleInset)
                .padding(.bottom, 8)
            }
        }
    }

    private var webSearchEngineSetting: some View {
        let title = L10n.text("웹 검색 엔진")
        return GeneralSettingRow(
            symbol: "globe",
            title: title,
            detail: L10n.text("검색창에서 ⌘ Enter를 누르면 이 검색 엔진을 사용합니다.")
        ) {
            Picker(title, selection: $webSearchEngine) {
                ForEach(SearchWebAddress.Engine.allCases, id: \.self) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var searchShortcutSetting: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralSettingRow(
                symbol: "magnifyingglass",
                title: L10n.text("검색창 단축키"),
                detail: L10n.text("다른 앱에서도 검색창을 엽니다.")
            ) {
                HStack(spacing: 8) {
                    CompactShortcutRecorderView(shortcut: Binding(
                        get: { runtime.store.searchShortcut },
                        set: {
                            runtime.store.searchShortcut = $0
                            runtime.saveAndReloadHotkeys()
                        }
                    ))
                    Button(L10n.text("기본값")) {
                        runtime.store.searchShortcut = .defaultSearch
                        runtime.saveAndReloadHotkeys()
                    }
                    .controlSize(.small)
                    .disabled(runtime.store.searchShortcut == .defaultSearch)
                }
            }
            if let error = runtime.hotkeys.searchRegistrationError {
                WookeyControlLabel(title: error, symbol: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                    .padding(.leading, GeneralSettingsLayout.titleInset)
                    .padding(.bottom, 8)
            }
        }
    }

    private func generalSwitch(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(theme.selectionTint)
    }

    private var generalDivider: some View {
        Divider().padding(.leading, GeneralSettingsLayout.titleInset)
    }

    private var updateSettings: some View {
        WookeySection(
            title: L10n.text("업데이트"),
            detail: L10n.text("새 버전을 자동으로 확인하고 Wookey 안에서 설치할 수 있습니다.")
        ) {
            PlainPanel {
                VStack(spacing: 0) {
                    UpdateSettingRow(
                        symbol: Page.updates.symbol,
                        title: L10n.text("자동으로 업데이트 확인"),
                        detail: L10n.text("하루에 한 번 새 버전을 확인합니다."),
                        isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.setAutomaticallyChecksForUpdates($0) }
                        )
                    )

                    Divider().padding(.leading, 42)

                    UpdateSettingRow(
                        symbol: "arrow.down.circle",
                        title: L10n.text("업데이트 자동 다운로드"),
                        detail: L10n.text("새 버전을 미리 받아 설치할 준비를 합니다."),
                        isOn: Binding(
                            get: { updates.automaticallyDownloadsUpdates },
                            set: { updates.setAutomaticallyDownloadsUpdates($0) }
                        ),
                        isEnabled: updates.allowsAutomaticUpdates
                    )

                    Divider().padding(.leading, 42)

                    HStack(spacing: 12) {
                        WookeyActionIcon(symbol: "info.circle", tint: .accent, size: 20)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("현재 버전 \(currentVersion)"))
                                .font(.headline)
                            Text(lastCheckedText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.text("지금 확인")) {
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
            WookeySection(title: L10n.text("확인 필요")) {
                PlainPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(runtime.hotkeys.registrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.workflows.first(where: { $0.id == id })?.name ?? L10n.text("워크플로")
                            WookeyControlLabel(
                                title: L10n.text("\(name): \(runtime.hotkeys.registrationErrors[id] ?? L10n.text("단축키 오류"))"),
                                symbol: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.hotkeys.layoutRegistrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.layouts.first(where: { $0.id == id })?.name ?? L10n.text("레이아웃")
                            WookeyControlLabel(
                                title: L10n.text("\(name): \(runtime.hotkeys.layoutRegistrationErrors[id] ?? L10n.text("단축키 오류"))"),
                                symbol: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.hotkeys.applicationRegistrationErrors.keys), id: \.self) { id in
                            let name = runtime.store.applicationShortcuts.first(where: { $0.id == id })?.displayName ?? L10n.text("앱")
                            WookeyControlLabel(
                                title: L10n.text("\(name): \(runtime.hotkeys.applicationRegistrationErrors[id] ?? L10n.text("단축키 오류"))"),
                                symbol: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                        ForEach(Array(runtime.applicationLaunchErrors.keys), id: \.self) { id in
                            let name = runtime.applicationName(runID: id) ?? L10n.text("앱")
                            WookeyControlLabel(
                                title: L10n.text("\(name): \(runtime.applicationLaunchErrors[id] ?? L10n.text("실행 오류"))"),
                                symbol: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                        }
                        if let error = runtime.store.lastPersistenceError {
                            WookeyControlLabel(title: error, symbol: "externaldrive.badge.exclamationmark")
                                .foregroundStyle(WookeyActionTint.rose.ink(in: colorScheme))
                        }
                    }
                    .font(.subheadline)
                }
            }
        } else {
            ContentUnavailableView {
                WookeyEmptyStateLabel(title: L10n.text("확인할 문제가 없습니다"), symbol: "checkmark.circle.fill")
            }
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
            return L10n.text("알 수 없음")
        }
    }

    private var lastCheckedText: String {
        guard let date = updates.lastUpdateCheckDate else {
            return L10n.text("아직 업데이트를 확인하지 않았습니다.")
        }
        return L10n.text("마지막 확인: \(date.formatted(date: .abbreviated, time: .shortened))")
    }
}

private enum GeneralSettingsLayout {
    static let iconWidth: CGFloat = 26
    static let columnSpacing: CGFloat = 12
    static let titleInset = iconWidth + columnSpacing
}

/// Icon, title and optional detail with trailing controls. `.general` is the
/// compact, column-aligned style of the general settings list; `.detailed` is
/// used by the update and permission rows.
private struct SettingRow<Control: View>: View {
    enum Style {
        case general, detailed

        var iconWidth: CGFloat { self == .general ? GeneralSettingsLayout.iconWidth : 30 }
        var verticalPadding: CGFloat { self == .general ? 7 : 12 }
        var minHeight: CGFloat? { self == .general ? 54 : nil }
    }

    var style: Style
    var symbol: String
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: GeneralSettingsLayout.columnSpacing) {
            WookeyActionIcon(symbol: symbol, tint: WookeyActionTint(symbol: symbol), size: 20)
                .frame(width: style.iconWidth)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: style == .general)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if style == .general { control.fixedSize() } else { control }
        }
        .padding(.vertical, style.verticalPadding)
        .frame(minHeight: style.minHeight)
    }
}

/// Keeps the general settings call sites unchanged.
private struct GeneralSettingRow<Control: View>: View {
    var symbol: String
    var title: String
    var detail: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        SettingRow(style: .general, symbol: symbol, title: title, detail: detail) { control }
    }
}

private struct UpdateSettingRow: View {
    @Environment(\.wookeyTheme) private var theme
    var symbol: String
    var title: String
    var detail: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        SettingRow(style: .detailed, symbol: symbol, title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(theme.selectionTint)
                .disabled(!isEnabled)
        }
    }
}

private struct PermissionSettingRow: View {
    var symbol: String
    var title: String
    var detail: String
    var granted: Bool
    var request: () -> Void
    var open: () -> Void

    var body: some View {
        SettingRow(style: .detailed, symbol: symbol, title: title, detail: detail) {
            StatusPill(title: granted ? L10n.text("허용됨") : L10n.text("꺼짐"), tone: granted ? .good : .neutral)
            Button(granted ? L10n.text("시스템 설정") : L10n.text("권한 켜기"), action: granted ? open : request)
        }
    }
}
