import AppKit
import SwiftUI
import WikeyCore

enum WikeyPageMetrics {
    static let padding: CGFloat = 26
    static let maximumWidth: CGFloat = 1000
}

var wikeyAssetBundle: Bundle {
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
            .interpolation(.high)
            .scaledToFit()
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
    func wikeyPrimaryButtonStyle() -> some View {
        buttonStyle(WikeyWarmButtonStyle(kind: .primary))
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

struct WikeyFilterPicker<Value: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedOption: Value?
    var title: String
    @Binding var selection: Value
    var options: [Value]
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { selection = option }
                    .buttonStyle(WikeyWarmButtonStyle(kind: .filter(selected: selection == option)))
                    .focused($focusedOption, equals: option)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            colorScheme == .dark
                ? Color(red: 0.22, green: 0.17, blue: 0.14)
                : Color(red: 0.96, green: 0.92, blue: 0.86),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onMoveCommand { direction in
            guard let focusedOption, let index = options.firstIndex(of: focusedOption) else { return }
            let nextIndex: Int
            switch direction {
            case .left: nextIndex = max(0, index - 1)
            case .right: nextIndex = min(options.count - 1, index + 1)
            default: return
            }
            selection = options[nextIndex]
            self.focusedOption = selection
        }
    }
}

private struct WikeyWarmButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case filter(selected: Bool)
    }

    var kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, kind: kind, isPressed: configuration.isPressed)
    }

    private struct Surface: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.controlSize) private var controlSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false
        var label: Configuration.Label
        var kind: Kind
        var isPressed: Bool

        private var palette: (text: Color, fill: [Color]) {
            switch kind {
            case .primary:
                (Color(red: 1, green: 0.98, blue: 0.92),
                 [Color(red: 0.55, green: 0.33, blue: 0.22), Color(red: 0.40, green: 0.22, blue: 0.14)])
            case .filter(selected: true):
                (Color(red: 0.27, green: 0.15, blue: 0.08),
                 [Color(red: 1, green: 0.89, blue: 0.59), Color(red: 0.97, green: 0.79, blue: 0.36)])
            case .filter(selected: false):
                (colorScheme == .dark
                    ? Color(red: 0.94, green: 0.85, blue: 0.74)
                    : Color(red: 0.32, green: 0.21, blue: 0.14),
                 [.clear, .clear])
            }
        }

        var body: some View {
            let primary = if case .primary = kind { true } else { false }
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            let palette = palette
            let charcoal = Color(white: 0.16).opacity(isPressed ? 0.23 : hovered ? 0.11 : 0)

            label
                .font(.system(size: primary ? 13 : 12))
                .foregroundStyle(palette.text)
                .padding(.horizontal, primary ? 13 : 11)
                .frame(minHeight: primary ? (controlSize == .large ? 32 : 30) : 25)
                .background {
                    shape.fill(LinearGradient(colors: palette.fill, startPoint: .top, endPoint: .bottom))
                    if primary {
                        shape.strokeBorder(.white.opacity(0.13), lineWidth: 1)
                    }
                    shape.fill(charcoal)
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.52)
                .onHover { hovered = isEnabled && $0 }
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
                    WikeyActionIcon(symbol: "xmark", tint: .neutral, size: 13)
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
            WikeyActionIcon(symbol: "trash", tint: .rose, size: 16)
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
                    WikeyControlLabel(title: "목록", symbol: "chevron.left")
                        .font(.subheadline)
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
                            WikeyActionIcon(symbol: "pencil", tint: .accent, size: 19)
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
        case "link": self = .graphite
        case "rectangle.3.group": self = .blue
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
    var size: CGFloat = 24

    private var artwork: String? {
        switch symbol {
        case "bolt", "bolt.fill": "WorkflowActionBolt"
        case "link": "WorkflowActionLink"
        case "doc.on.clipboard": "WorkflowActionTemplate"
        case "app", "macwindow", "dock.rectangle": "WorkflowActionApplication"
        case "doc": "WorkflowActionDocument"
        case "rectangle.3.group": "WorkflowActionLayout"
        case "keyboard": "WorkflowActionKeyboard"
        case "clock": "WorkflowActionWait"
        case "photo": "WorkflowActionPhoto"
        case "paperclip": "WorkflowActionAttachment"
        case "return", "arrow.turn.down.left": "WorkflowActionReturn"
        case "plus", "plus.circle": "WikeyCommandAdd"
        case "play.fill": "WikeyCommandPlay"
        case "gearshape", "slider.horizontal.3": "WikeyCommandSettings"
        case "magnifyingglass": "WikeyCommandSearch"
        case "pencil": "WikeyCommandEdit"
        case "trash": "WikeyCommandDelete"
        case "doc.on.doc": "WikeyCommandCopy"
        case "xmark", "xmark.circle.fill": "WikeyCommandClose"
        case "arrow.up.right", "arrow.up", "arrow.down": "WikeyCommandOpen"
        case "chevron.left", "chevron.right": "WikeyCommandChevron"
        case "arrow.clockwise", "arrow.clockwise.circle.fill", "arrow.triangle.2.circlepath": "WikeyCommandRefresh"
        case "stop.fill": "WikeyCommandStop"
        case "checkmark.circle.fill": "WikeyCommandCheck"
        case "bold": "WikeyCommandBold"
        case "italic": "WikeyCommandItalic"
        case "underline": "WikeyCommandUnderline"
        default: nil
        }
    }

    private var rotation: Angle {
        switch symbol {
        case "chevron.left": .degrees(180)
        case "arrow.up": .degrees(-45)
        case "arrow.down": .degrees(135)
        default: .zero
        }
    }

    var body: some View {
        Group {
            if let artwork {
                let isSilverChain = symbol == "link"
                let darkModeLift = colorScheme == .dark && (isSilverChain || artwork.hasPrefix("WikeyCommand"))
                let silverHighlight = isSilverChain ? 0.095 : 0
                Image(artwork, bundle: wikeyAssetBundle)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .saturation(isSilverChain ? 0 : 0.78)
                    .brightness(silverHighlight + (darkModeLift ? 0.19 : 0))
                    .rotationEffect(rotation)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: min(size, 15), weight: .regular))
                    .foregroundStyle(tint.ink(in: colorScheme).gradient)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WikeyControlLabel: View {
    var title: String
    var symbol: String

    var body: some View {
        Label {
            Text(title).fontWeight(.regular)
        } icon: {
            WikeyActionIcon(symbol: symbol, tint: WikeyActionTint(symbol: symbol), size: 15)
        }
        .accessibilityLabel(title)
    }
}

extension Button where Label == WikeyControlLabel {
    init(_ title: String, wikeyIcon symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            WikeyControlLabel(title: title, symbol: symbol)
        }
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
                .font(.system(size: 13, weight: .regular))
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
        return ink.opacity(selected ? 0.105 : filled ? 0.05 : 0)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        label
            .background {
                shape.fill(fill)
                    .overlay {
                        if focused {
                            shape.inset(by: 1).strokeBorder(ink.opacity(0.62), lineWidth: 1)
                        }
                        if glossy {
                            shape.fill(LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), .clear],
                                startPoint: .top, endPoint: .bottom
                            ))
                            shape.strokeBorder(LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.13 : 0.65), Color.black.opacity(0.075)],
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
