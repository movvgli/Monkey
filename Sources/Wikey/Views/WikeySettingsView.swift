import SwiftUI
import WikeyCore

struct WikeySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(WikeyRuntime.self) private var runtime
    @Environment(UpdateController.self) private var updates

    private enum Page: String, CaseIterable {
        case general = "일반"
        case permissions = "권한"
        case sync = "동기화"
        case updates = "업데이트"
        case diagnostics = "문제 확인"

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .permissions: "lock.shield"
            case .sync: "icloud"
            case .updates: "arrow.down.circle"
            case .diagnostics: "exclamationmark.triangle"
            }
        }
    }

    @State private var page: Page = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("설정 항목", selection: $page) {
                ForEach(Page.allCases, id: \.self) { page in
                    Label(
                        page == .diagnostics && hasErrors ? "문제 확인 •" : page.rawValue,
                        systemImage: page.symbol
                    )
                        .tag(page)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
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
                        Text("Wikey를 응용 프로그램 폴더에서 실행해 주세요")
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
                        Text("입력 모니터링을 켰다면 Wikey를 다시 열어 주세요")
                            .font(.headline)
                        Text("macOS는 이 권한을 새로 시작한 앱에 적용합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Wikey 다시 열기") {
                        runtime.permissions.relaunchApplication()
                    }
                }
                .padding(14)
                .background(Color.wikeyAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button("권한 상태 새로고침", systemImage: "arrow.clockwise") {
                runtime.permissions.refresh()
            }
            .buttonStyle(WikeyPastelButtonStyle(tint: .periwinkle))
        }
    }

    private var general: some View {
        WikeySection(title: "일반") {
            PlainPanel {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "dock.rectangle")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dock에 Wikey 표시")
                                .font(.headline)
                            Text("끄면 메뉴 막대에만 아이콘을 표시합니다.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "Dock에 Wikey 표시",
                            isOn: Binding(
                                get: { runtime.dockIcon.isVisible },
                                set: { runtime.setDockIconVisible($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 12)

                    Divider().padding(.leading, 42)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("로그인 시 Wikey 실행")
                                    .font(.headline)
                                Text("메인 창은 열지 않고 메뉴 막대와 단축키만 준비합니다.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(
                                "로그인 시 실행",
                                isOn: Binding(
                                    get: { runtime.loginItem.isEnabled },
                                    set: { runtime.loginItem.setEnabled($0) }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

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
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var updateSettings: some View {
        WikeySection(
            title: "업데이트",
            detail: "새 버전을 자동으로 확인하고 Wikey 안에서 설치할 수 있습니다."
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
