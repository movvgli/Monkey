import AppKit
import SwiftUI

enum WookeyCharacter: String, CaseIterable {
    static let storageKey = "selectedCharacter"

    case wookey
    case sharkey

    var title: String { self == .wookey ? "우키" : "샤키" }
    var companionTitle: String { self == .wookey ? "바나나" : "산호" }

    var shelfArtwork: String {
        self == .wookey ? "FileShelfFolderWookey" : "FileShelfFolderSharkey"
    }

    var companionArtwork: String {
        self == .wookey ? "LightningMascot" : "CoralMascot"
    }
}

enum WookeyIconTheme: String, CaseIterable {
    static let storageKey = "selectedIconTheme"

    case threeDimensional
    case fluffy

    var title: String { self == .threeDimensional ? "3D" : "플러피" }

    // Fluffy variants use the same asset name with a Fluffy prefix.
    func asset(_ preferred: String, fallback: String? = nil) -> String {
        if self == .fluffy, hasArtwork(preferred) { return "Fluffy" + preferred }
        guard let fallback, !hasArtwork(preferred, themed: false) else { return preferred }
        return asset(fallback)
    }

    func hasArtwork(_ name: String, themed: Bool = true) -> Bool {
        let prefix = themed && self == .fluffy ? "Fluffy" : ""
        return wookeyAssetBundle.image(forResource: NSImage.Name(prefix + name)) != nil
    }

    @MainActor
    func applyDockIcon() {
        let name = self == .fluffy ? "FluffyAppIcon" : "AppIcon"
        var canvas = NSRect(x: 0, y: 0, width: 512, height: 512)
        guard let artwork = wookeyAssetBundle.image(forResource: NSImage.Name(name)),
              let bitmap = artwork.cgImage(forProposedRect: &canvas, context: nil, hints: nil),
              let context = CGContext(
                data: nil, width: Int(canvas.width), height: Int(canvas.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            NSApp.applicationIconImage = nil
            return
        }
        // Match the visible size of the system Dock icons while preserving the centered canvas.
        let padding = canvas.width * (46.0 / 512.0)
        context.interpolationQuality = .high
        context.draw(bitmap, in: canvas.insetBy(dx: padding, dy: padding))
        NSApp.applicationIconImage = context.makeImage().map { NSImage(cgImage: $0, size: canvas.size) }
    }
}

enum WookeyMenuBarIcon: String, CaseIterable, Identifiable {
    static let visibilityKey = "showsMenuBarIcon"
    static let styleKey = "menuBarIconStyle"

    // Keep the stored values so existing menu bar choices retain their role.
    case character = "monkey"
    case companion = "banana"

    var id: Self { self }

    func title(for character: WookeyCharacter) -> String {
        self == .character ? character.title : character.companionTitle
    }

    func artwork(for character: WookeyCharacter) -> String {
        switch (self, character) {
        case (.character, .wookey): "MenuBarWookey"
        case (.companion, .wookey): "MenuBarBanana"
        case (.character, .sharkey): "MenuBarSharkey"
        case (.companion, .sharkey): "MenuBarCoral"
        }
    }

    func image(
        character: WookeyCharacter,
        theme: WookeyIconTheme,
        activity: Activity? = nil,
        accessibilityLabel: String? = nil
    ) -> Image {
        let label = accessibilityLabel ?? title(for: character)
        let assetName = theme.asset(artwork(for: character), fallback: artwork(for: .wookey))
        guard let activity,
              let base = wookeyAssetBundle.image(forResource: NSImage.Name(assetName)),
              let badge = NSImage(systemSymbolName: activity.symbol, accessibilityDescription: nil) else {
            return Image(assetName, bundle: wookeyAssetBundle, label: Text(label)).renderingMode(.original)
        }

        let statusImage = NSImage(size: base.size, flipped: false) { bounds in
            base.draw(in: bounds)
            let badgeRect = CGRect(x: bounds.maxX - 8, y: bounds.minY, width: 8, height: 8)
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.clear)
                context.fillEllipse(in: badgeRect.insetBy(dx: -1, dy: -1))
                context.restoreGState()
            }
            badge.draw(in: badgeRect)
            return true
        }
        statusImage.isTemplate = false
        statusImage.accessibilityDescription = label
        return Image(nsImage: statusImage).renderingMode(.original)
    }

    enum Activity {
        case running
        case failed

        var symbol: String {
            switch self {
            case .running: "clock.fill"
            case .failed: "exclamationmark.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .running: "Wookey, 워크플로 실행 중"
            case .failed: "Wookey, 마지막 실행 실패"
            }
        }
    }
}
