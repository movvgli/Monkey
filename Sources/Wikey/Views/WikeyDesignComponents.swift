import AppKit
import SwiftUI
import WikeyCore

enum WikeyTheme: String, CaseIterable {
    static let storageKey = "appearanceTheme"
    static let defaultTheme = Self.yellow

    case white, yellow, brown, dark

    var title: String {
        switch self {
        case .white: "화이트"
        case .yellow: "옐로우"
        case .brown: "브라운"
        case .dark: "다크"
        }
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    var canvas: Color {
        switch self {
        case .white: Color(white: 0.99)
        case .yellow: Color(red: 1, green: 0.963, blue: 0.865)
        case .brown: Color(red: 0.938, green: 0.865, blue: 0.794)
        case .dark: Color(red: 0.125, green: 0.101, blue: 0.085)
        }
    }

    var panel: Color {
        switch self {
        case .white: .white
        case .yellow: Color(red: 1, green: 0.982, blue: 0.926)
        case .brown: Color(red: 0.976, green: 0.92, blue: 0.864)
        case .dark: Color(red: 0.184, green: 0.15, blue: 0.123)
        }
    }

    var sidebar: Color {
        switch self {
        case .white: Color(white: 0.956)
        case .yellow: Color(red: 0.966, green: 0.91, blue: 0.763)
        case .brown: Color(red: 0.877, green: 0.768, blue: 0.674)
        case .dark: Color(red: 0.09, green: 0.074, blue: 0.065)
        }
    }

    var accent: Color { Self.controlInk(in: colorScheme) }

    static let banana = Color(red: 0.97, green: 0.79, blue: 0.36)
    static let cocoa = Color(red: 0.27, green: 0.15, blue: 0.08)

    static func controlInk(in scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 0.86, blue: 0.59) : Color(red: 0.40, green: 0.22, blue: 0.12)
    }
}

private struct WikeyThemeKey: EnvironmentKey {
    static let defaultValue = WikeyTheme.defaultTheme
}

private struct WikeyPrimarySurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wikeyTheme: WikeyTheme {
        get { self[WikeyThemeKey.self] }
        set { self[WikeyThemeKey.self] = newValue }
    }

    fileprivate var wikeyPrimarySurface: Bool {
        get { self[WikeyPrimarySurfaceKey.self] }
        set { self[WikeyPrimarySurfaceKey.self] = newValue }
    }
}

struct WikeyThemeScope: ViewModifier {
    @AppStorage(WikeyTheme.storageKey) private var theme = WikeyTheme.defaultTheme

    func body(content: Content) -> some View {
        content
            .environment(\.wikeyTheme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.accent)
    }
}

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
    @Environment(\.wikeyTheme) private var theme
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let isDark = theme == .dark
        shape.fill(
            LinearGradient(
                colors: [theme.panel, theme.canvas, theme.sidebar],
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
    func wikeyLauncherGlass(theme: WikeyTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(theme.panel.opacity(0.78)), in: shape)
        } else {
            background(theme.panel.opacity(0.96), in: shape)
        }
        #else
        background(theme.panel.opacity(0.96), in: shape)
        #endif
    }
}

struct WikeyFilterPicker<Value: Hashable>: View {
    @Environment(\.wikeyTheme) private var theme
    @FocusState private var focusedOption: Value?
    var title: String
    @Binding var selection: Value
    var options: [Value]
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { selection = option }
                    .buttonStyle(WikeyWarmButtonStyle(kind: .filter(
                        selected: selection == option, focused: focusedOption == option
                    )))
                    .focusable()
                    .focused($focusedOption, equals: option)
                    .focusEffectDisabled()
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                    .onKeyPress(.leftArrow) { move(from: option, offset: -1) }
                    .onKeyPress(.rightArrow) { move(from: option, offset: 1) }
            }
        }
        .padding(3)
        .background(
            theme.sidebar,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func move(from option: Value, offset: Int) -> KeyPress.Result {
        guard let index = options.firstIndex(of: option),
              options.indices.contains(index + offset) else { return .handled }
        let next = options[index + offset]
        selection = next
        focusedOption = next
        return .handled
    }
}

private struct WikeyWarmButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case filter(selected: Bool, focused: Bool)
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
                (WikeyTheme.cocoa,
                 [Color(red: 0.91, green: 0.76, blue: 0.57), Color(red: 0.79, green: 0.58, blue: 0.38)])
            case .filter(selected: true, focused: _):
                (WikeyTheme.cocoa, [Color(red: 1, green: 0.89, blue: 0.59), WikeyTheme.banana])
            case .filter(selected: false, focused: _):
                (WikeyTheme.controlInk(in: colorScheme), [.clear, .clear])
            }
        }

        var body: some View {
            let primary = if case .primary = kind { true } else { false }
            let focused = if case .filter(_, let focused) = kind { focused } else { false }
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            let palette = palette
            let charcoal = Color(white: 0.16).opacity(isPressed ? 0.23 : hovered ? 0.11 : 0)

            label
                .font(.system(size: primary ? 13 : 12))
                .foregroundStyle(palette.text)
                .environment(\.wikeyPrimarySurface, primary)
                .padding(.horizontal, primary ? 13 : 11)
                .frame(minHeight: primary ? (controlSize == .large ? 32 : 30) : 25)
                .background {
                    shape.fill(LinearGradient(colors: palette.fill, startPoint: .top, endPoint: .bottom))
                    if primary {
                        shape.strokeBorder(WikeyTheme.cocoa.opacity(0.17), lineWidth: 1)
                    }
                    shape.fill(charcoal)
                    if focused {
                        shape.strokeBorder(palette.text.opacity(0.8), lineWidth: 1)
                    }
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
    @Environment(\.wikeyTheme) private var theme
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
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
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
    @Environment(\.wikeyTheme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            return WikeyTheme.controlInk(in: colorScheme)
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
    @Environment(\.wikeyPrimarySurface) private var onPrimarySurface
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

    private func artworkTint(_ artwork: String) -> Color {
        switch artwork {
        case "WikeyCommandAdd":
            colorScheme == .dark && !onPrimarySurface
                ? Color(red: 0.97, green: 0.72, blue: 0.44)
                : Color(red: 0.51, green: 0.29, blue: 0.14)
        case "WikeyCommandClose":
            colorScheme == .dark
                ? Color(red: 1, green: 0.39, blue: 0.38)
                : Color(red: 0.91, green: 0.23, blue: 0.23)
        default: .white
        }
    }

    var body: some View {
        Group {
            if let artwork {
                let isSilverChain = symbol == "link"
                let darkModeLift = colorScheme == .dark && (isSilverChain || artwork.hasPrefix("WikeyCommand"))
                let highlight = isSilverChain ? 0.095 : artwork == "WikeyCommandClose" ? 0.25 : 0
                let darkLift = darkModeLift && !onPrimarySurface ? 0.19 : 0
                Image(artwork, bundle: wikeyAssetBundle)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .saturation(isSilverChain ? 0 : 0.78)
                    .brightness(highlight + darkLift)
                    .colorMultiply(artworkTint(artwork))
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
            ink: WikeyTheme.controlInk(in: colorScheme),
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
        let selectedFill = WikeyTheme.banana.opacity(colorScheme == .dark ? 0.20 : 0.48)
        if isEnabled && (isPressed || isHovering) {
            if selected { return selectedFill }
            let isDark = colorScheme == .dark
            let charcoal = Color(white: isDark ? 0.34 : 0.15)
            let hoverOpacity = isDark ? 0.54 : 0.12
            return charcoal.opacity(isPressed ? hoverOpacity * 1.4 : hoverOpacity)
        }
        return selected ? selectedFill : ink.opacity(filled ? 0.08 : 0)
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
