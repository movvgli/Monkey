import AppKit
import SwiftUI
import WookeyCore

enum WookeyTheme: String, CaseIterable {
    static let storageKey = "appearanceTheme"
    static let defaultTheme = Self.white

    case white, yellow, sky, brown, dark

    var title: String {
        switch self {
        case .white: L10n.text("화이트")
        case .yellow: L10n.text("옐로우")
        case .sky: L10n.text("하늘색")
        case .brown: L10n.text("브라운")
        case .dark: L10n.text("다크")
        }
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    var canvas: Color {
        switch self {
        case .white: Color(white: 0.99)
        case .yellow: Color(red: 1, green: 0.963, blue: 0.865)
        case .sky: Color(red: 0.925, green: 0.969, blue: 1)
        case .brown: Color(red: 0.938, green: 0.865, blue: 0.794)
        case .dark: Color(red: 0.125, green: 0.101, blue: 0.085)
        }
    }

    var panel: Color {
        switch self {
        case .white: .white
        case .yellow: Color(red: 1, green: 0.982, blue: 0.926)
        case .sky: Color(red: 0.969, green: 0.989, blue: 1)
        case .brown: Color(red: 0.976, green: 0.92, blue: 0.864)
        case .dark: Color(red: 0.184, green: 0.15, blue: 0.123)
        }
    }

    var sidebar: Color {
        switch self {
        case .white: Color(white: 0.956)
        case .yellow: Color(red: 0.966, green: 0.91, blue: 0.763)
        case .sky: Color(red: 0.852, green: 0.922, blue: 0.980)
        case .brown: Color(red: 0.877, green: 0.768, blue: 0.674)
        case .dark: Color(red: 0.09, green: 0.074, blue: 0.065)
        }
    }

    var accent: Color {
        self == .sky ? Color(red: 0.14, green: 0.31, blue: 0.47) : Self.controlInk(in: colorScheme)
    }

    var selectionTint: Color {
        self == .sky ? Color(red: 0.53, green: 0.77, blue: 0.94) : Self.banana
    }

    var selectionHighlight: Color {
        self == .sky ? Color(red: 0.75, green: 0.88, blue: 0.99) : Color(red: 1, green: 0.89, blue: 0.59)
    }

    var selectionInk: Color { self == .sky ? accent : Self.cocoa }

    static let banana = Color(red: 0.97, green: 0.79, blue: 0.36)
    static let cocoa = Color(red: 0.27, green: 0.15, blue: 0.08)

    static func controlInk(in scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 0.86, blue: 0.59) : Color(red: 0.40, green: 0.22, blue: 0.12)
    }
}

private struct WookeyThemeKey: EnvironmentKey {
    static let defaultValue = WookeyTheme.defaultTheme
}

extension EnvironmentValues {
    var wookeyTheme: WookeyTheme {
        get { self[WookeyThemeKey.self] }
        set { self[WookeyThemeKey.self] = newValue }
    }
}

struct WookeyThemeScope: ViewModifier {
    @AppStorage(WookeyTheme.storageKey) private var theme = WookeyTheme.defaultTheme

    func body(content: Content) -> some View {
        content
            .environment(\.wookeyTheme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.accent)
            .font(.pretendard(.body))
            .buttonStyle(WookeyGlossyButtonStyle())
    }
}

enum WookeyPageMetrics {
    static let padding: CGFloat = 26
    static let maximumWidth: CGFloat = 1000
    static let headerSpacing: CGFloat = 18
}

var wookeyAssetBundle: Bundle {
    #if SWIFT_PACKAGE
    .module
    #else
    .main
    #endif
}

struct WookeyMascot: View {
    @AppStorage(WookeyCharacter.storageKey) private var character = WookeyCharacter.wookey
    @AppStorage(WookeyIconTheme.storageKey) private var iconTheme = WookeyIconTheme.threeDimensional
    var size: CGFloat

    var body: some View {
        Image(iconTheme.asset(character.companionArtwork, fallback: WookeyCharacter.wookey.companionArtwork),
              bundle: wookeyAssetBundle)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct WookeyGlossyPanel: View {
    @Environment(\.wookeyTheme) private var theme
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
    @ViewBuilder
    func wookeyLauncherGlass(theme: WookeyTheme) -> some View {
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

struct WookeyFilterPicker<Value: Hashable>: View {
    @Environment(\.wookeyTheme) private var theme
    @FocusState private var focusedOption: Value?
    var title: String
    @Binding var selection: Value
    var options: [Value]
    var icon: ((Value) -> String)? = nil
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = icon?(option) {
                            WookeyActionIcon(symbol: symbol, tint: WookeyActionTint(symbol: symbol), size: 15)
                        }
                        Text(label(option))
                    }
                }
                    .buttonStyle(WookeyFilterButtonStyle(
                        selected: selection == option, focused: focusedOption == option
                    ))
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

private struct WookeyFilterButtonStyle: ButtonStyle {
    var selected: Bool
    var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, selected: selected, focused: focused, isPressed: configuration.isPressed)
    }

    private struct Surface: View {
        @Environment(\.wookeyTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false
        var label: Configuration.Label
        var selected: Bool
        var focused: Bool
        var isPressed: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            let textColor = selected ? theme.selectionInk : theme.accent
            let fill: [Color] = selected
                ? [theme.selectionHighlight, theme.selectionTint]
                : [.clear, .clear]
            let charcoal = Color(white: 0.16).opacity(isPressed ? 0.23 : hovered ? 0.11 : 0)

            label
                .font(.pretendard(size: 12))
                .foregroundStyle(textColor)
                .padding(.horizontal, 11)
                .frame(minHeight: 25)
                .background {
                    shape.fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                    shape.fill(charcoal)
                    if focused {
                        shape.strokeBorder(textColor.opacity(0.8), lineWidth: 1)
                    }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.52)
                .onHover { hovered = isEnabled && $0 }
        }
    }
}

struct WookeyPageHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.pretendard(size: 28, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.pretendard(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .frame(minHeight: 54)
    }
}

struct WookeySearchField: View {
    @Environment(\.wookeyTheme) private var theme
    var prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            WookeyActionIcon(symbol: "magnifyingglass", tint: .neutral, size: 16)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    WookeyActionIcon(symbol: "xmark", tint: .neutral, size: 13)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.text("검색 지우기"))
                .accessibilityLabel(L10n.text("검색 지우기"))
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

struct WookeySaveStatus: View {
    @Environment(WookeyRuntime.self) private var runtime
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(
            runtime.store.lastPersistenceError == nil ? L10n.text("자동 저장됨") : L10n.text("저장 실패"),
            systemImage: runtime.store.lastPersistenceError == nil ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.pretendard(.caption))
        .foregroundStyle(runtime.store.lastPersistenceError == nil ? Color.secondary : WookeyActionTint.rose.ink(in: colorScheme))
        .help(runtime.store.lastPersistenceError ?? L10n.text("변경 사항을 자동으로 저장합니다."))
    }
}

struct WookeyDeleteButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            WookeyActionIcon(symbol: "trash", tint: .rose, size: 16)
        }
        .buttonStyle(WookeyGlossyButtonStyle(tint: .rose, iconOnly: true))
        .help(title)
        .accessibilityLabel(title)
    }
}

struct WookeyEditorHeader<Actions: View>: View {
    @FocusState private var isEditingName: Bool
    @Binding var title: String
    var subtitle: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let onBack {
                Button(L10n.text("목록"), wookeyIcon: "chevron.left", action: onBack)
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.small)
                    .help(L10n.text("목록으로 돌아가기 (⌘[)"))
                    .accessibilityLabel(L10n.text("목록으로 돌아가기"))
                    .keyboardShortcut("[", modifiers: [.command])
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Button { isEditingName = true } label: {
                            WookeyActionIcon(symbol: "pencil", tint: .accent, size: 19)
                        }
                        .buttonStyle(WookeyGlossyButtonStyle(iconOnly: true))
                        .controlSize(.small)
                        .accessibilityLabel(L10n.text("이름 수정"))
                        .help(L10n.text("이름 수정"))

                        TextField(L10n.text("이름"), text: $title)
                            .textFieldStyle(.plain)
                            .focused($isEditingName)
                            .font(.pretendard(size: 25, weight: .semibold))
                            .accessibilityLabel(L10n.text("이름"))
                            .help(L10n.text("이름 편집"))
                    }
                    Text(subtitle)
                        .font(.pretendard(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
        }
        .padding(.horizontal, WookeyPageMetrics.padding)
        .padding(.vertical, 16)
    }
}

struct WookeySection<Content: View>: View {
    var title: String
    var detail: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.pretendard(.headline))
                if let detail {
                    Text(detail)
                        .font(.pretendard(.subheadline))
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
            .font(.pretendard(size: 11, weight: .medium))
            .foregroundStyle(isMuted ? Color.secondary : Color.wookeyInk(in: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isMuted ? Color.secondary.opacity(0.08) : Color.wookeyInk(in: colorScheme).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .accessibilityLabel(L10n.text("단축키 \(text)"))
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
                .font(.pretendard(.caption, weight: .medium))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.color.opacity(0.1), in: Capsule())
    }
}

struct PlainPanel<Content: View>: View {
    @Environment(\.wookeyTheme) private var theme
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

let wookeyTemplateSymbol = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: nil) != nil
    ? "pencil.and.scribble"
    : "square.and.pencil"
let wookeyDrawerSymbol = "archivebox"

enum WookeyActionTint {
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
        case "doc", "doc.on.clipboard", wookeyTemplateSymbol, "photo", "paperclip", "folder", wookeyDrawerSymbol, "lightbulb": self = .amber
        case "keyboard", "return", "arrow.turn.down.left", "clock": self = .neutral
        default: self = .accent
        }
    }

    func ink(in colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        switch self {
        case .accent:
            return WookeyTheme.controlInk(in: colorScheme)
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
    var wookeyIcon: (symbol: String, tint: WookeyActionTint) {
        let symbol = switch self {
        case .copyTemplate: wookeyTemplateSymbol
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
        return (symbol, WookeyActionTint(symbol: symbol))
    }
}

extension Workflow {
    var wookeyIcon: (symbol: String, tint: WookeyActionTint) {
        guard actions.count == 1, let action = actions.first else { return ("bolt", .accent) }
        return action.wookeyIcon
    }
}

struct WookeyActionIcon: View {
    @Environment(\.wookeyTheme) private var theme
    @AppStorage(WookeyIconTheme.storageKey) private var iconTheme = WookeyIconTheme.threeDimensional
    @Environment(\.colorScheme) private var colorScheme
    var symbol: String
    var tint: WookeyActionTint
    var size: CGFloat = 24

    private var artwork: String? {
        switch symbol {
        case "bolt", "bolt.fill": "WorkflowActionBolt"
        case "link": "WorkflowActionLink"
        case wookeyTemplateSymbol: "WorkflowActionTemplateNote"
        case "doc.on.clipboard": "WorkflowActionTemplate"
        case "app", "macwindow", "dock.rectangle": "WorkflowActionApplication"
        case "doc": "WorkflowActionDocument"
        case "folder": "WookeyShelfFolder"
        case wookeyDrawerSymbol: "WookeyShelfDrawer"
        case "rectangle.3.group": "WorkflowActionLayout"
        case "keyboard": "WorkflowActionKeyboard"
        case "clock": "WorkflowActionWait"
        case "photo": "WorkflowActionPhoto"
        case "paperclip": "WorkflowActionAttachment"
        case "return", "arrow.turn.down.left": "WorkflowActionReturn"
        case "plus", "plus.circle": "WookeyCommandAdd"
        case "play.fill": "WookeyCommandPlay"
        case "gearshape", "slider.horizontal.3": "WookeyCommandSettings"
        case "magnifyingglass": "WookeyCommandSearch"
        case "globe": "WookeySettingsWebSearch"
        case "pencil": "WookeyCommandEdit"
        case "trash": "WookeyCommandDelete"
        case "doc.on.doc": "WookeyCommandCopy"
        case "xmark", "xmark.circle.fill": "WookeyCommandClose"
        case "arrow.up.right", "arrow.up", "arrow.down": "WookeyCommandOpen"
        case "chevron.left", "chevron.right": "WookeyCommandChevron"
        case "arrow.clockwise", "arrow.clockwise.circle.fill", "arrow.triangle.2.circlepath": "WookeyCommandRefresh"
        case "stop.fill": "WookeyCommandStop"
        case "power": "WookeyCommandPower"
        case "checkmark.circle.fill": "WookeyCommandCheck"
        case "bold": "WookeyCommandBold"
        case "italic": "WookeyCommandItalic"
        case "underline": "WookeyCommandUnderline"
        case "lock.shield", "lock.shield.fill": "WookeySettingsPermissions"
        case "icloud": "WookeySettingsSync"
        case "stethoscope": "WookeySettingsDiagnostics"
        case "paintpalette": "WookeySettingsPalette"
        case "lightbulb": "WookeySettingsSensitivity"
        case "face.smiling": "WookeySettingsCharacter"
        case "square.stack.3d.up": "WookeySettingsIconTheme"
        case "menubar.rectangle": "WookeySettingsMenuBar"
        case "door.left.hand.open": "WookeySettingsLogin"
        case "accessibility": "WookeySettingsAccessibility"
        case "arrow.down.circle": "WookeySettingsDownload"
        case "info.circle", "info.circle.fill": "WookeySettingsInfo"
        case "exclamationmark.triangle", "exclamationmark.triangle.fill": "WookeySettingsWarning"
        case "externaldrive.badge.exclamationmark": "WookeySettingsStorage"
        case "app.badge.checkmark": "WorkflowActionApplication"
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
                Image(iconTheme.asset(artwork), bundle: wookeyAssetBundle)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .rotationEffect(rotation)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.80, weight: .medium))
                    .foregroundStyle(tint == .accent ? theme.accent : tint.ink(in: colorScheme))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WookeyEmptyStateLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            WookeyActionIcon(symbol: symbol, tint: WookeyActionTint(symbol: symbol), size: 44)
        }
    }
}

struct WookeyControlLabel: View {
    var title: String
    var symbol: String

    var body: some View {
        Label {
            Text(title).fontWeight(.regular)
        } icon: {
            WookeyActionIcon(symbol: symbol, tint: WookeyActionTint(symbol: symbol), size: 15)
        }
        .accessibilityLabel(title)
    }
}

extension Button where Label == WookeyControlLabel {
    init(_ title: String, wookeyIcon symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            WookeyControlLabel(title: title, symbol: symbol)
        }
    }
}

struct WookeyHoverButtonStyle: ButtonStyle {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var selected = false
    var focused = false

    func makeBody(configuration: Configuration) -> some View {
        WookeyHoverSurface(
            label: configuration.label,
            ink: theme.accent,
            selected: selected,
            filled: false,
            cornerRadius: 9,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            focused: focused
        )
    }
}

struct WookeyGlossyButtonStyle: ButtonStyle {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    var tint: WookeyActionTint = .accent
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        let ink = tint == .accent ? theme.accent : tint.ink(in: colorScheme)
        let compact = controlSize == .small || controlSize == .mini
        let minimumSize: CGFloat = compact ? 29 : 36
        return WookeyHoverSurface(
            label: configuration.label
                .font(.pretendard(size: 13, weight: .regular))
                .foregroundStyle(ink)
                .padding(.horizontal, iconOnly ? 0 : compact ? 9 : 12)
                .frame(minWidth: minimumSize, minHeight: minimumSize),
            ink: theme.accent,
            selected: false,
            filled: true,
            cornerRadius: 10,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            glossy: true
        )
    }
}

private struct WookeyHoverSurface<Label: View>: View {
    @Environment(\.wookeyTheme) private var theme
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
        let selectedFill = theme.selectionTint.opacity(colorScheme == .dark ? 0.20 : 0.48)
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
