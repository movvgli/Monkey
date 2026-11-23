import AppKit
import SwiftUI
import WikeyCore

enum WikeyPageMetrics {
    static let padding: CGFloat = 26
    static let maximumWidth: CGFloat = 1000
}

private var wikeyAssetBundle: Bundle {
    #if SWIFT_PACKAGE
    .module
    #else
    .main
    #endif
}

struct WikeyMascot: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat

    var body: some View {
        Image("LightningMascot", bundle: wikeyAssetBundle)
            .resizable()
            .scaledToFit()
            .saturation(0)
            .contrast(1.1)
            .colorMultiply(Color(red: 1, green: 0.80, blue: 0.39))
            .frame(width: size, height: size)
            .shadow(color: colorScheme == .dark ? .white.opacity(0.26) : .black.opacity(0.16),
                    radius: colorScheme == .dark ? 1 : 3,
                    y: colorScheme == .dark ? -1 : 2)
            .accessibilityHidden(true)
    }
}

struct WikeyGlossyPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let isDark = colorScheme == .dark
        shape.fill(
            LinearGradient(
                colors: isDark
                    ? [Color(white: 0.28), Color(white: 0.21), Color(white: 0.17)]
                    : [.white, Color(white: 0.97), Color(white: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            shape.strokeBorder(LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.24 : 0.95), Color.black.opacity(isDark ? 0.28 : 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
    }
}

extension View {
    @ViewBuilder
    func wikeyPrimaryButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    @ViewBuilder
    func wikeyLauncherGlass() -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.thickMaterial, in: shape)
        }
        #else
        background(.thickMaterial, in: shape)
        #endif
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
        .buttonStyle(WikeyGlossyButtonStyle(tint: .rose, iconOnly: true))
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
                            WikeyActionIcon(symbol: "pencil", tint: .accent)
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
    case accent
    case graphite
    case blue
    case teal
    case amber
    case rose
    case neutral

    init(symbol: String) {
        switch symbol {
        case "link", "rectangle.3.group": self = .blue
        case "app", "arrow.left.arrow.right": self = .teal
        case "doc", "doc.on.clipboard", "photo", "paperclip": self = .amber
        case "keyboard", "return", "arrow.turn.down.left", "clock": self = .neutral
        default: self = .accent
        }
    }

    func ink(in colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        switch self {
        case .accent:
            return .wikeyInk(in: colorScheme)
        case .graphite:
            return Color(white: isDark ? 0.77 : 0.35)
        case .blue:
            return isDark ? Color(red: 0.61, green: 0.78, blue: 0.99) : Color(red: 0.19, green: 0.36, blue: 0.59)
        case .teal:
            return isDark ? Color(red: 0.51, green: 0.84, blue: 0.74) : Color(red: 0.11, green: 0.40, blue: 0.33)
        case .amber:
            return isDark ? Color(red: 1, green: 0.76, blue: 0.50) : Color(red: 0.55, green: 0.30, blue: 0.09)
        case .rose:
            return isDark ? Color(red: 1, green: 0.57, blue: 0.59) : Color(red: 0.68, green: 0.14, blue: 0.24)
        case .neutral:
            return .secondary
        }
    }
}

extension WorkflowAction {
    var wikeyIcon: (symbol: String, tint: WikeyActionTint) {
        let symbol = switch self {
        case .copyTemplate: "doc.on.clipboard"
        case .openURL: "link"
        case .launchApplication: "app"
        case .openFile: "doc"
        case .applyLayout: "rectangle.3.group"
        case .pressKey: "keyboard"
        case .runWorkflow: "bolt"
        case .pasteImages: "photo"
        case .pasteFiles: "paperclip"
        case .wait: "clock"
        }
        return (symbol, WikeyActionTint(symbol: symbol))
    }
}

struct WikeyActionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    var symbol: String
    var tint: WikeyActionTint
    var size: CGFloat = 28

    private var artwork: String? {
        switch symbol {
        case "bolt": "WorkflowActionBolt"
        case "link": "WorkflowActionLink"
        case "doc.on.clipboard": "WorkflowActionTemplate"
        case "app": "WorkflowActionApplication"
        case "doc": "WorkflowActionDocument"
        case "rectangle.3.group": "WorkflowActionLayout"
        case "keyboard": "WorkflowActionKeyboard"
        case "clock": "WorkflowActionWait"
        case "photo": "WorkflowActionPhoto"
        case "paperclip": "WorkflowActionAttachment"
        case "return", "arrow.turn.down.left": "WorkflowActionReturn"
        default: nil
        }
    }

    var body: some View {
        Group {
            if let artwork {
                Image(artwork, bundle: wikeyAssetBundle)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size > 30 ? 16 : 13, weight: .medium))
                    .foregroundStyle(tint.ink(in: colorScheme))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WikeyHoverButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var selected = false
    var focused = false
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
            isEnabled: isEnabled,
            focused: focused
        )
    }
}

struct WikeyGlossyButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var tint: WikeyActionTint = .accent
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
            isEnabled: isEnabled,
            glossy: true
        )
    }
}

private struct WikeyHoverSurface<Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    var label: Label
    var ink: Color
    var selected: Bool
    var filled: Bool
    var cornerRadius: CGFloat
    var isPressed: Bool
    var isEnabled: Bool
    var focused = false
    var glossy = false

    private var fill: Color {
        if isEnabled && (isPressed || isHovering) {
            let isDark = colorScheme == .dark
            let charcoal = Color(white: isDark ? 0.34 : 0.15)
            let hoverOpacity = isDark ? 0.54 : 0.12
            return charcoal.opacity(isPressed ? hoverOpacity * 1.4 : hoverOpacity)
        }
        return ink.opacity(selected ? 0.14 : filled ? 0.075 : 0)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        label
            .background {
                shape.fill(fill)
                    .overlay {
                        if focused {
                            shape.inset(by: 1).strokeBorder(ink.opacity(0.75), lineWidth: 1)
                        }
                        if glossy {
                            shape.fill(LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.13 : 0.65), .clear],
                                startPoint: .top, endPoint: .bottom
                            ))
                            shape.strokeBorder(LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.18 : 0.8), Color.black.opacity(0.11)],
                                startPoint: .top, endPoint: .bottom
                            ))
                        }
                    }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = $0 }
    }
}
