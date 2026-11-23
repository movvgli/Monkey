import AppKit
import SwiftUI
import WikeyCore

enum WikeyPageMetrics {
    static let padding: CGFloat = 26
    static let maximumWidth: CGFloat = 1000
}

struct WikeyMascot: View {
    var size: CGFloat

    var body: some View {
        Image("LightningMascot", bundle: assetBundle)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var assetBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

struct WikeyLavenderPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let isDark = colorScheme == .dark
        shape.fill(
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.20, green: 0.15, blue: 0.29), Color(red: 0.26, green: 0.18, blue: 0.32)]
                    : [Color(red: 0.94, green: 0.91, blue: 1), Color(red: 0.99, green: 0.94, blue: 0.98)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay {
            shape.strokeBorder(isDark ? Color.white.opacity(0.10) : Color.wikeyAccent.opacity(0.13))
        }
    }
}

struct WikeyPageHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
    }
}

struct WikeySearchField: View {
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("검색 지우기")
                .accessibilityLabel("검색 지우기")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }
}

struct WikeySaveStatus: View {
    @Environment(WikeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(
            runtime.store.lastPersistenceError == nil ? "자동 저장됨" : "저장 실패",
            systemImage: runtime.store.lastPersistenceError == nil ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(runtime.store.lastPersistenceError == nil ? Color.secondary : WikeyActionTint.rose.ink(in: colorScheme))
        .help(runtime.store.lastPersistenceError ?? "변경 사항을 자동으로 저장합니다.")
    }
}

struct WikeyDeleteButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(WikeyPastelButtonStyle(tint: .rose, iconOnly: true))
        .help(title)
        .accessibilityLabel(title)
    }
}

struct WikeyEditorHeader<Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isEditingName: Bool
    @Binding var title: String
    var subtitle: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Label("목록", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.wikeyInk(in: colorScheme))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                }
                .buttonStyle(WikeyHoverButtonStyle())
                .help("목록으로 돌아가기 (⌘[)")
                .accessibilityLabel("목록으로 돌아가기")
                .keyboardShortcut("[", modifiers: [.command])
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Button { isEditingName = true } label: {
                            WikeyActionIcon(symbol: "pencil", tint: .lavender)
                        }
                        .buttonStyle(WikeyHoverButtonStyle())
                        .accessibilityLabel("이름 수정")
                        .help("이름 수정")

                        TextField("이름", text: $title)
                            .textFieldStyle(.plain)
                            .focused($isEditingName)
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                            .accessibilityLabel("이름")
                            .help("이름 편집")
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
        }
        .padding(.horizontal, WikeyPageMetrics.padding)
        .padding(.vertical, 16)
    }
}

struct WikeySection<Content: View>: View {
    var title: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var text: String
    var isMuted = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(isMuted ? Color.secondary : Color.wikeyInk(in: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isMuted ? Color.secondary.opacity(0.08) : Color.wikeyInk(in: colorScheme).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .accessibilityLabel("단축키 \(text)")
    }
}

struct StatusPill: View {
    enum Tone {
        case good
        case attention
        case neutral

        var color: Color {
            switch self {
            case .good: .green
            case .attention: .orange
            case .neutral: .secondary
            }
        }
    }

    var title: String
    var tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.1), in: Capsule())
    }
}

struct PlainPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

enum WikeyActionTint {
    case lavender
    case periwinkle
    case mint
    case peach
    case rose
    case neutral

    func ink(in colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        switch self {
        case .lavender:
            return .wikeyInk(in: colorScheme)
        case .periwinkle:
            return isDark ? Color(red: 0.72, green: 0.77, blue: 1) : Color(red: 0.30, green: 0.36, blue: 0.67)
        case .mint:
            return isDark ? Color(red: 0.64, green: 0.88, blue: 0.80) : Color(red: 0.23, green: 0.42, blue: 0.37)
        case .peach:
            return isDark ? Color(red: 1, green: 0.76, blue: 0.66) : Color(red: 0.65, green: 0.32, blue: 0.25)
        case .rose:
            return isDark ? Color(red: 1, green: 0.57, blue: 0.59) : Color(red: 0.68, green: 0.14, blue: 0.24)
        case .neutral:
            return .secondary
        }
    }
}

extension WorkflowAction {
    var wikeyIcon: (symbol: String, tint: WikeyActionTint) {
        switch self {
        case .copyTemplate: ("doc.on.clipboard", .lavender)
        case .openURL: ("link", .periwinkle)
        case .launchApplication: ("app", .mint)
        case .openFile: ("doc", .peach)
        case .applyLayout: ("rectangle.3.group", .lavender)
        case .pressKey: ("keyboard", .neutral)
        case .runWorkflow: ("bolt", .lavender)
        case .pasteImages: ("photo", .peach)
        case .pasteFiles: ("paperclip", .peach)
        case .wait: ("clock", .neutral)
        }
    }
}

struct WikeyActionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var symbol: String
    var tint: WikeyActionTint
    var size: CGFloat = 28

    var body: some View {
        let ink = tint.ink(in: colorScheme)
        Image(systemName: symbol)
            .font(.system(size: size > 30 ? 16 : 13, weight: .medium))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(ink.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct WikeyHoverButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var selected = false
    var filled = false
    var cornerRadius: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        WikeyHoverSurface(
            label: configuration.label,
            ink: .wikeyInk(in: colorScheme),
            selected: selected,
            filled: filled,
            cornerRadius: cornerRadius,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled
        )
    }
}

struct WikeyPastelButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var tint: WikeyActionTint = .lavender
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        let ink = tint.ink(in: colorScheme)
        return WikeyHoverSurface(
            label: configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, iconOnly ? 0 : 12)
                .frame(minWidth: 36, minHeight: 36),
            ink: ink,
            selected: false,
            filled: true,
            cornerRadius: 10,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled
        )
    }
}

private struct WikeyHoverSurface<Label: View>: View {
    @State private var isHovering = false
    var label: Label
    var ink: Color
    var selected: Bool
    var filled: Bool
    var cornerRadius: CGFloat
    var isPressed: Bool
    var isEnabled: Bool

    private var fillOpacity: Double {
        if isPressed { return 0.24 }
        if isHovering && isEnabled { return 0.17 }
        if selected { return 0.14 }
        return filled ? 0.075 : 0
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        label
            .background(ink.opacity(fillOpacity), in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = $0 }
    }
}
