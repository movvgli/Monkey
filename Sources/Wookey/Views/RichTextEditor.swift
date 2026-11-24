import AppKit
import SwiftUI
import WookeyCore

@MainActor
final class RichTextEditorController {
    weak var textView: NSTextView?
    var onDocumentChange: ((NSAttributedString) -> Void)?
    /// Called on every edit, including uncommitted IME composition, with the visible text.
    var onTextChange: ((String) -> Void)?
    private var pendingDocument: NSAttributedString?

    func load(_ document: NSAttributedString) {
        pendingDocument = document
        if let textView { applyPendingDocument(to: textView) }
    }

    func attach(_ textView: NSTextView) {
        self.textView = textView
        applyPendingDocument(to: textView)
    }

    func toggleBold() { toggleFontTrait(.boldFontMask) }
    func toggleItalic() { toggleFontTrait(.italicFontMask) }

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = effectiveRange(in: textView)
        if range.length == 0 {
            let current = textView.typingAttributes[.underlineStyle] as? Int ?? 0
            if current == 0 {
                textView.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                textView.typingAttributes.removeValue(forKey: .underlineStyle)
            }
            return
        }
        let current = storage.attribute(.underlineStyle, at: max(0, min(range.location, max(storage.length - 1, 0))), effectiveRange: nil) as? Int ?? 0
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        if current == 0 { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        else { storage.removeAttribute(.underlineStyle, range: range) }
        textView.didChangeText()
    }

    func addLink() {
        guard let textView, textView.selectedRange().length > 0 else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = L10n.text("링크 추가")
        alert.informativeText = L10n.text("선택한 텍스트에 연결할 주소를 입력하세요.")
        let field = NSTextField(string: "https://")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.text("추가"))
        alert.addButton(withTitle: L10n.text("취소"))
        guard alert.runModal() == .alertFirstButtonReturn, let url = URL(string: field.stringValue),
              let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.addAttribute(.link, value: url, range: range)
        textView.didChangeText()
    }

    func insertBullet() {
        guard let textView else { return }
        // insertText registers undo and posts textDidChange, which emits the change.
        textView.insertText("• ", replacementRange: textView.selectedRange())
    }

    func insertImage() {
        guard let textView else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("템플릿에 넣을 이미지 선택")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url),
              image.isValid else {
            return
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.allowsTextAttachmentView = false

        let naturalSize = image.size
        let containerWidth = textView.textContainer?.containerSize.width ?? naturalSize.width
        let maximumWidth = max(containerWidth - 16, 1)
        let scale = naturalSize.width > maximumWidth ? maximumWidth / naturalSize.width : 1
        attachment.bounds = NSRect(
            x: 0,
            y: 0,
            width: max(naturalSize.width * scale, 1),
            height: max(naturalSize.height * scale, 1)
        )

        let attributed = NSAttributedString(attachment: attachment)
        let range = textView.selectedRange()
        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: attributed.string) else { return }
        storage.replaceCharacters(in: range, with: attributed)
        textView.didChangeText()
    }

    /// Commits any in-progress IME composition so it is included in the next emitted document.
    func commitMarkedText() {
        guard let textView, textView.hasMarkedText() else { return }
        textView.unmarkText()
        textView.inputContext?.discardMarkedText()
        emitChange()
    }

    func emitChange() {
        guard let textView, let storage = textView.textStorage else { return }
        (textView as? TemplateTextView)?.refreshPreviewContrast()
        onTextChange?(storage.string)
        // Marked text is an in-progress IME composition (e.g. Korean); emit once it is committed.
        guard !textView.hasMarkedText() else { return }
        onDocumentChange?(NSAttributedString(attributedString: storage))
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = effectiveRange(in: textView)
        if range.length == 0 {
            let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 15)
            let manager = NSFontManager.shared
            let hasTrait = manager.traits(of: font).contains(trait)
            textView.typingAttributes[.font] = hasTrait
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let manager = NSFontManager.shared
            let hasTrait = manager.traits(of: font).contains(trait)
            let converted = hasTrait ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    private func effectiveRange(in textView: NSTextView) -> NSRange {
        let selected = textView.selectedRange()
        if selected.length > 0 { return selected }
        return NSRange(location: selected.location, length: 0)
    }

    private func applyPendingDocument(to textView: NSTextView) {
        guard let pendingDocument, let storage = textView.textStorage else { return }
        storage.setAttributedString(pendingDocument)
        if storage.length == 0 {
            textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 14)]
        }
        (textView as? TemplateTextView)?.refreshPreviewContrast()
        self.pendingDocument = nil
    }
}

final class TemplateTextView: NSTextView {
    var focusesWhenAttached = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusesWhenAttached, window != nil else { return }
        focusesWhenAttached = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPreviewContrast()
    }

    func refreshPreviewContrast() {
        guard let storage = textStorage, storage.length > 0, let layout = layoutManager else { return }
        let document = NSRange(location: 0, length: storage.length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: document)
        guard effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else { return }

        // Temporary attributes affect drawing without changing the RTFD or its clipboard representation.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let page = luminance(of: backgroundColor, over: 0) ?? 0
            storage.enumerateAttributes(in: document) { attributes, range, _ in
                let highlight = attributes[.backgroundColor] as? NSColor
                let backdrop = highlight.flatMap { luminance(of: $0, over: page) } ?? page
                let text = attributes[.foregroundColor] as? NSColor
                let isLink = attributes[.link] != nil
                let defaultInk: NSColor = isLink ? .linkColor : .textColor
                guard let ink = luminance(of: isLink ? defaultInk : text ?? defaultInk, over: backdrop) else { return }

                let contrast = (max(ink, backdrop) + 0.05) / (min(ink, backdrop) + 0.05)
                if contrast < 4.5 || (text == nil && !isLink) {
                    let readableInk: NSColor = contrast >= 4.5 ? defaultInk : backdrop > 0.18 ? .black : .white
                    layout.addTemporaryAttribute(.foregroundColor, value: readableInk, forCharacterRange: range)
                }
            }
        }
    }

    private func luminance(of color: NSColor, over backdrop: CGFloat) -> CGFloat? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }

        func linear(_ value: CGFloat) -> CGFloat {
            let channel = max(0, min(1, value))
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        let value = 0.2126 * linear(rgb.redComponent)
            + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
        return value * rgb.alphaComponent + backdrop * (1 - rgb.alphaComponent)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Environment(\.wookeyTheme) private var theme
    var controller: RichTextEditorController
    var focusesOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(theme.panel)

        let textView = TemplateTextView(usingTextLayoutManager: false)
        textView.focusesWhenAttached = focusesOnAppear
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(theme.panel)
        textView.insertionPointColor = .textColor
        textView.setAccessibilityLabel(L10n.text("템플릿 본문"))
        textView.textContainerInset = NSSize(width: 22, height: 20)
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 15)]
        textView.delegate = context.coordinator
        scroll.documentView = textView
        controller.attach(textView)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.controller = controller
        if let textView = nsView.documentView as? TemplateTextView {
            let background = NSColor(theme.panel)
            if textView.backgroundColor != background {
                nsView.backgroundColor = background
                textView.backgroundColor = background
                textView.refreshPreviewContrast()
            }
            if controller.textView !== textView { controller.attach(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var controller: RichTextEditorController
        init(controller: RichTextEditorController) { self.controller = controller }

        func textDidChange(_ notification: Notification) {
            controller.emitChange()
        }
    }
}
