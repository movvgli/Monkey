import Foundation

public enum SearchWebAddress {
    public static func searchURL(for query: String) -> URL? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: term)]
        // Google treats literal plus signs in query values as spaces.
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
