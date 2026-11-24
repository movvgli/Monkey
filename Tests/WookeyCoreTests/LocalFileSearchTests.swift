import Foundation
import Testing
@testable import WookeyCore

struct LocalFileSearchTests {
    @Test func escapesSpotlightSyntaxInFilenameTerms() {
        let predicate = LocalFileSearch.predicate(for: ["보고서", #"a*"b?\c"#])
        #expect(predicate == #"(kMDItemFSName == "*보고서*"cd || kMDItemDisplayName == "*보고서*"cd) && (kMDItemFSName == "*a\*\"b\?\\c*"cd || kMDItemDisplayName == "*a\*\"b\?\\c*"cd)"#)
    }

    @Test func exactFilenameRanksBeforeNamesThatContainIt() {
        let exact = LocalFileSearch.Match(url: URL(fileURLWithPath: "/tmp/보고서.pdf"), name: "보고서", isFolder: false)
        let prefix = LocalFileSearch.Match(url: URL(fileURLWithPath: "/tmp/보고서.pdf.bak"), name: "보고서.pdf.bak", isFolder: false)
        let substring = LocalFileSearch.Match(url: URL(fileURLWithPath: "/tmp/이전 보고서.pdf"), name: "이전 보고서.pdf", isFolder: false)
        let matches = [substring, prefix, exact].sorted { LocalFileSearch.Match.precedes($0, $1, for: "보고서.pdf") }
        #expect(matches.map(\.url) == [exact.url, prefix.url, substring.url])
    }

    @Test func exactPathFindsAFileAndDirectoryWithoutIndexing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("검색 테스트.txt")
        try Data().write(to: file)

        let files = await LocalFileSearch.search(matching: file.path)
        let folders = await LocalFileSearch.search(matching: folder.path)
        #expect(files.first?.url.path == file.path)
        #expect(files.first?.isFolder == false)
        #expect(folders.first?.isFolder == true)
    }
}
