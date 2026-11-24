import AppKit
import CoreText
import SwiftUI

enum WookeyTypography {
    enum Weight: String, CaseIterable {
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "SemiBold"
        case bold = "Bold"

        var name: String { "Pretendard-\(rawValue)" }

        var nativeWeight: NSFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    private static let registerFonts: Void = {
        for weight in Weight.allCases {
            guard let url = wookeyAssetBundle.url(forResource: weight.name, withExtension: "otf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func native(size: CGFloat, weight: Weight = .regular) -> NSFont {
        _ = registerFonts
        return NSFont(name: weight.name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight.nativeWeight)
    }
}

extension Font {
    static func pretendard(_ style: TextStyle, weight: WookeyTypography.Weight? = nil) -> Font {
        let size: CGFloat = switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .subheadline: 12
        case .caption, .footnote: 11
        case .caption2: 10
        default: 13
        }
        let font = WookeyTypography.native(size: size, weight: weight ?? (style == .headline ? .semibold : .regular))
        return .custom(font.fontName, size: size, relativeTo: style)
    }

    static func pretendard(size: CGFloat, weight: WookeyTypography.Weight = .regular) -> Font {
        Font(WookeyTypography.native(size: size, weight: weight))
    }
}
