import Foundation

public enum SearchWebAddress {
    public enum Engine: String, CaseIterable, Sendable {
        case google, naver, daum, nate

        public static let storageKey = "webSearchEngine"

        public var title: String {
            switch self {
            case .google: "Google"
            case .naver: L10n.text("네이버")
            case .daum: L10n.text("다음 검색")
            case .nate: L10n.text("네이트")
            }
        }

        fileprivate var endpoint: (host: String, path: String, queryKey: String) {
            switch self {
            case .google: ("www.google.com", "/search", "q")
            case .naver: ("search.naver.com", "/search.naver", "query")
            case .daum: ("search.daum.net", "/search", "q")
            case .nate: ("search.nate.com", "/search/all.html", "q")
            }
        }
    }

    public static func searchURL(for query: String, engine: Engine = .google) -> URL? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        let endpoint = engine.endpoint
        var components = URLComponents()
        components.scheme = "https"
        components.host = endpoint.host
        components.path = endpoint.path
        components.queryItems = [URLQueryItem(name: endpoint.queryKey, value: term)]
        // Search sites can interpret literal plus signs as spaces.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    public static func parse(_ query: String) -> URL? {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty,
              input.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }

        let hasScheme = input.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil
        guard let components = URLComponents(string: hasScheme ? input : "https://\(input)"),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty,
              hasScheme || isDomain(host),
              let url = components.url else { return nil }
        return url
    }

    private static func isDomain(_ host: String) -> Bool {
        let domain = host.hasSuffix(".") ? host.dropLast() : host[...]
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let suffix = labels.last, suffix.contains(where: \.isLetter) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
