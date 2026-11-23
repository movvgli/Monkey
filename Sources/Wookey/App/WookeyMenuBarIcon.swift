import AppKit
import SwiftUI

enum WookeyMenuBarIcon: String, CaseIterable, Identifiable {
    static let visibilityKey = "showsMenuBarIcon"
    static let styleKey = "menuBarIconStyle"

    case wookey = "monkey"
    case banana

    var id: Self { self }

    var title: String {
        switch self {
        case .wookey: "우키"
        case .banana: "바나나"
        }
    }

    var assetName: String {
        switch self {
        case .wookey: "MenuBarWookey"
        case .banana: "MenuBarBanana"
        }
    }

    func image(activity: Activity? = nil, accessibilityLabel: String? = nil) -> Image {
        let label = accessibilityLabel ?? title
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
