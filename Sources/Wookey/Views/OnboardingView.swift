import AppKit
import SwiftUI
import WookeyCore

struct OnboardingView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(WookeyRuntime.self) private var runtime
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @Binding var isPresented: Bool
    @State private var page = 0
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            onboardingHeader

            ZStack {
                if page == 0 {
                    introduction
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    permissions
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            onboardingFooter
        }
        .frame(width: 660, height: 580)
        .onAppear {
            // Start from the current login item state so finishing onboarding doesn't turn it off.
            runtime.loginItem.refresh()
            launchAtLogin = runtime.loginItem.isEnabled
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 14) {
            WookeyMascot(size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text("Wookey 시작하기"))
                    .font(.system(size: 25, weight: .semibold))
                Text(page == 0 ? L10n.text("무엇을 할 수 있는지 먼저 알아볼게요.") : L10n.text("필요한 기능만 선택해서 켜세요."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.wookeyInk(in: colorScheme) : Color.secondary.opacity(0.18))
                        .frame(width: index == page ? 24 : 8, height: 8)
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.text("온보딩 \(page + 1)단계, 총 2단계"))
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("반복하는 일을\n단축키 하나로 끝내세요"))
                    .font(.system(size: 32, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.text("자주 하는 작업을 원하는 순서로 연결하면 Wookey가 어디서든 빠르게 실행합니다."))
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                OnboardingFeatureCard(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    title: L10n.text("여러 작업을 하나의 워크플로로"),
                    detail: L10n.text("앱 실행, 웹사이트, 템플릿과 창 배치를 순서대로 연결합니다.")
                )
                OnboardingFeatureCard(
                    systemImage: "bolt.fill",
                    title: L10n.text("어디서나 빠르게 실행"),
                    detail: L10n.text("한 번 또는 두 단계 단축키와 메뉴 막대에서 바로 실행합니다.")
                )
                OnboardingFeatureCard(
                    systemImage: "lock.shield.fill",
                    title: L10n.text("기본은 내 Mac에 저장"),
                    detail: L10n.text("설정은 이 Mac에 보관합니다. 원하면 설정에서 iCloud 동기화를 직접 켤 수 있습니다.")
                )
            }

            HStack(spacing: 10) {
                OnboardingStepLabel(number: 1, title: L10n.text("워크플로 만들기"))
                WookeyActionIcon(symbol: "chevron.right", tint: .neutral, size: 12)
                OnboardingStepLabel(number: 2, title: L10n.text("동작 추가"))
                WookeyActionIcon(symbol: "chevron.right", tint: .neutral, size: 12)
                OnboardingStepLabel(number: 3, title: L10n.text("단축키로 실행"))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("필요한 기능만 권한을 켜세요"))
                    .font(.system(size: 28, weight: .bold))
                Text(L10n.text("기본 워크플로는 권한 없이도 사용할 수 있고, 필요한 기능은 나중에 설정할 수 있습니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                OnboardingPermissionRow(
                    systemImage: "macwindow",
                    title: L10n.text("창 배치와 자동 붙여넣기"),
                    detail: L10n.text("손쉬운 사용 권한을 사용합니다."),
                    granted: runtime.permissions.accessibilityGranted,
                    request: runtime.permissions.requestAccessibility
                )
                Divider().padding(.leading, 60)
                OnboardingPermissionRow(
                    systemImage: "keyboard",
                    title: L10n.text("두 단계 단축키"),
                    detail: L10n.text("손쉬운 사용과 입력 모니터링 권한을 사용합니다."),
                    granted: runtime.permissions.inputMonitoringGranted,
                    request: runtime.permissions.requestInputMonitoring
                )
            }
            .padding(.horizontal, 16)
            .background(
                theme.panel,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }

            if runtime.permissions.inputMonitoringRestartRecommended {
                HStack(spacing: 10) {
                    WookeyActionIcon(symbol: "arrow.clockwise", tint: .accent, size: 16)
                    Text(L10n.text("입력 모니터링을 켠 뒤에는 Wookey를 다시 열어야 적용됩니다."))
                        .font(.subheadline)
                    Spacer()
                    Button(L10n.text("다시 열기")) {
                        runtime.permissions.relaunchApplication()
                    }
                }
                .padding(12)
                .background(Color.wookeyInk(in: colorScheme).opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Toggle(L10n.text("Mac 로그인 시 Wookey 실행"), isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .tint(theme.selectionTint)
                Text(L10n.text("메인 창은 띄우지 않고 메뉴 막대와 단축키만 준비합니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.text("권한을 켜지 않아도 앱 실행, 웹사이트 열기와 템플릿 클립보드 복사는 사용할 수 있습니다."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var onboardingFooter: some View {
        HStack {
            if page == 0 {
                Button(L10n.text("건너뛰기")) { complete(enableLoginItem: nil) }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .tint(theme.accent)
                Spacer()
                Button(L10n.text("다음")) {
                    withAnimation(.easeInOut(duration: 0.24)) { page = 1 }
                }
                .buttonStyle(WookeyGlossyButtonStyle())
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.text("이전")) {
                    withAnimation(.easeInOut(duration: 0.24)) { page = 0 }
                }
                .buttonStyle(WookeyGlossyButtonStyle())
                .tint(theme.accent)
                Spacer()
                Button(L10n.text("나중에 설정")) { complete(enableLoginItem: nil) }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .tint(theme.accent)
                Button(L10n.text("Wookey 시작")) { complete(enableLoginItem: launchAtLogin) }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .background(theme.panel)
    }

    /// `enableLoginItem` of nil (skipping) leaves the login item as it is.
    private func complete(enableLoginItem: Bool?) {
        if let enableLoginItem, enableLoginItem != runtime.loginItem.isEnabled {
            runtime.loginItem.setEnabled(enableLoginItem)
        }
        didCompleteOnboarding = true
        isPresented = false
    }
}

private struct OnboardingFeatureCard: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 14) {
            WookeyActionIcon(symbol: systemImage, tint: WookeyActionTint(symbol: systemImage), size: 22)
                .frame(width: 40, height: 40)
                .background(Color.wookeyInk(in: colorScheme).opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.panel,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }
}

private struct OnboardingStepLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    var number: Int
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.wookeyInk(in: colorScheme))
                .frame(width: 20, height: 20)
                .background(Color.wookeyInk(in: colorScheme).opacity(0.1), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingPermissionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var systemImage: String
    var title: String
    var detail: String
    var granted: Bool
    var request: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            WookeyActionIcon(symbol: granted ? "checkmark.circle.fill" : systemImage, tint: .accent, size: 20)
                .frame(width: 32, height: 32)
                .background(
                    (granted ? Color.green : Color.wookeyInk(in: colorScheme)).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                StatusPill(title: L10n.text("완료"), tone: .good)
            } else {
                Button(L10n.text("권한 켜기"), action: request)
            }
        }
        .padding(.vertical, 14)
    }
}
