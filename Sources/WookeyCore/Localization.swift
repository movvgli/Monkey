import Foundation

public enum L10n {
    private final class BundleMarker {}

    private static let english: Bundle? = {
        let languages = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        let supported = languages.lazy.compactMap { Locale.Language(identifier: $0).languageCode?.identifier }
            .first { $0 == "ko" || $0 == "en" }
        guard supported == "en" else {
            return nil
        }

        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle(for: BundleMarker.self)
        #endif
        return resources.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))
    }()

    public static func text(_ message: Message) -> String {
        let format = lookup(message.key)
        guard !message.arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: message.arguments)
    }

    // Some existing raw values are also persisted. Localize at the point of display.
    public static func label(_ key: String) -> String { lookup(key) }

    private static func lookup(_ key: String) -> String {
        english?.localizedString(forKey: key, value: key, table: "Wookey") ?? key
    }

    public struct Message: ExpressibleByStringInterpolation {
        fileprivate let key: String
        fileprivate let arguments: [String]

        public init(stringLiteral value: String) {
            key = value
            arguments = []
        }

        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.format
            arguments = stringInterpolation.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            fileprivate var format = ""
            fileprivate var arguments: [String] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                format.reserveCapacity(literalCapacity)
                arguments.reserveCapacity(interpolationCount)
            }

            public mutating func appendLiteral(_ value: String) {
                format += value.replacingOccurrences(of: "%", with: "%%")
            }

            public mutating func appendInterpolation<T>(_ value: T) {
                format += "%@"
                arguments.append(String(describing: value))
            }
        }
    }
}
