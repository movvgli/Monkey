import CoreServices
import Foundation

public enum LocalFileSearch {
    public struct Match: Sendable {
        public let url: URL
        public let name: String
        public let isFolder: Bool

        public func hasExactName(_ text: String) -> Bool {
            [name, url.lastPathComponent].contains {
                $0.compare(text, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
            }
        }

        private func rank(for text: String) -> Int {
            if hasExactName(text) { return 0 }
            return name.range(of: text, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) == nil ? 2 : 1
        }

        static func precedes(_ lhs: Self, _ rhs: Self, for text: String) -> Bool {
            let left = lhs.rank(for: text)
            let right = rhs.rank(for: text)
            if left != right { return left < right }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.url.path < rhs.url.path
        }
    }

    public static func search(matching text: String) async -> [Match] {
        await Task.detached(priority: .userInitiated) {
            if text.hasPrefix("/") || text.hasPrefix("~/") { return exactPath(text) }
            return indexedMatches(text)
        }.value
    }

    private static func exactPath(_ text: String) -> [Match] {
        let path = (text as NSString).expandingTildeInPath
        var folder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &folder) else { return [] }
        let url = URL(fileURLWithPath: path, isDirectory: folder.boolValue)
        return [Match(url: url, name: FileManager.default.displayName(atPath: path), isFolder: folder.boolValue)]
    }

    static func predicate(for terms: [String]) -> String {
        terms.map { term in
            // Escape Spotlight's string delimiter and wildcard operators in literal filenames.
            let literal = term.reduce(into: "") { escaped, character in
                if ["\\", "\"", "*", "?"].contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
            return "(kMDItemFSName == \"*\(literal)*\"cd || kMDItemDisplayName == \"*\(literal)*\"cd)"
        }.joined(separator: " && ")
    }

    private static func indexedMatches(_ text: String) -> [Match] {
        let terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty, let query = MDQueryCreate(nil, predicate(for: terms) as CFString, nil, nil) else { return [] }
        MDQuerySetSearchScope(query, [kMDQueryScopeComputerIndexed] as CFArray, 0)
        MDQuerySetMaxCount(query, 120)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }

        var paths = Set<String>()
        let matches: [Match] = (0..<MDQueryGetResultCount(query)).compactMap { index in
            guard let result = MDQueryGetResultAtIndex(query, index) else { return nil }
            let item = Unmanaged<MDItem>.fromOpaque(result).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  paths.insert(path).inserted else { return nil }
            let types = MDItemCopyAttribute(item, kMDItemContentTypeTree) as? [String] ?? []
            let isFolder = types.contains("public.folder")
            let url = URL(fileURLWithPath: path, isDirectory: isFolder)
            let name = MDItemCopyAttribute(item, kMDItemDisplayName) as? String ?? url.lastPathComponent
            return Match(url: url, name: name, isFolder: isFolder)
        }
        return matches.sorted { Match.precedes($0, $1, for: text) }
    }
}
