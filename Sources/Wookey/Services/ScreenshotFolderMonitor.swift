import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ScreenshotFolderMonitor {
    struct Capture: Sendable {
        let name: String
        let date: Date
        let type: String
        let data: Data
    }

    private struct FileID: Hashable {
        let resource: AnyHashable
        let createdAt: Date
    }

    private struct PendingFile {
        let url: URL
        let checkUntil: Date
    }

    private static let maximumImageBytes = 32 * 1024 * 1024
    private static let screenshotAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    private static let screenshotNamePattern =
        #"\A(?:스크린샷 \d{4}-\d{2}-\d{2} (?:오전 |오후 )?\d{1,2}\.\d{2}\.\d{2}|Screenshot \d{4}-\d{2}-\d{2} at \d{1,2}\.\d{2}\.\d{2}(?: [AP]M)?)(?: \(\d+\))?\z"#
    private static let fileKeys: Set<URLResourceKey> = [
        .creationDateKey, .fileResourceIdentifierKey, .isRegularFileKey, .isSymbolicLinkKey,
    ]

    private var directory: URL?
    private var recordingSince: Date?
    private var lastScan: Date?
    private var earliestCapture = Date.distantFuture
    private var lastDirectoryChange: Date?
    private var handled = Set<FileID>()
    private var recordedNames = Set<String>()
    private var pending: [FileID: PendingFile] = [:]

    static func configuredDirectory() -> URL? {
        let preferences = UserDefaults(suiteName: "com.apple.screencapture")
        if let target = preferences?.string(forKey: "target-screenshot") ?? preferences?.string(forKey: "target"),
           target != "file" {
            return nil
        }
        let location = preferences?.string(forKey: "location-screenshot") ?? preferences?.string(forKey: "location")
        if let location, !location.isEmpty {
            let path = (location as NSString).expandingTildeInPath
            if path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    func scan(directory: URL?, recordingSince: Date, now: Date) throws -> [Capture] {
        if self.directory != directory || self.recordingSince != recordingSince {
            earliestCapture = self.recordingSince == recordingSince ? max(recordingSince, lastScan ?? now) : recordingSince
            self.directory = directory
            self.recordingSince = recordingSince
            lastDirectoryChange = nil
            handled.removeAll()
            recordedNames.removeAll()
            pending.removeAll()
        }
        lastScan = now
        guard let directory else { return [] }

        // Read a fresh timestamp for folders that stay open between scans.
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.resolvingSymlinksInPath().path)
        let changedAt = attributes[.modificationDate] as? Date
        if changedAt == nil || lastDirectoryChange != changedAt {
            try findNewFiles(in: directory, now: now)
            lastDirectoryChange = changedAt
        }

        var captures: [Capture] = []
        var remainingBytes = Self.maximumImageBytes
        for (id, file) in pending {
            let name = Self.timestampedScreenshotName(file.url)
            // An image converter can leave both the original and the WebP in the folder.
            let alreadyRecorded = name.map(recordedNames.contains) ?? false
            if !alreadyRecorded {
                if let capture = readCapture(file.url, date: id.createdAt, hasScreenshotName: name != nil) {
                    guard capture.data.count <= remainingBytes else { break }
                    captures.append(capture)
                    remainingBytes -= capture.data.count
                    if let name { recordedNames.insert(name) }
                } else if now < file.checkUntil {
                    continue
                }
            }
            handled.insert(id)
            pending.removeValue(forKey: id)
        }
        return captures.sorted { $0.date < $1.date }
    }

    private func findNewFiles(in directory: URL, now: Date) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(Self.fileKeys), options: .skipsHiddenFiles
        )
        for url in urls {
            guard let type = UTType(filenameExtension: url.pathExtension),
                  type.conforms(to: .image) || type.conforms(to: .pdf),
                  let values = try? url.resourceValues(forKeys: Self.fileKeys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let createdAt = values.creationDate, createdAt >= earliestCapture else { continue }

            let resource = (values.fileResourceIdentifier as? NSObject).map(AnyHashable.init) ?? AnyHashable(url)
            let id = FileID(resource: resource, createdAt: createdAt)
            guard !handled.contains(id) else { continue }
            // The filename can appear before macOS finishes writing the image and its metadata.
            let checkUntil = pending[id]?.checkUntil ?? now.addingTimeInterval(10)
            pending[id] = PendingFile(url: url, checkUntil: checkUntil)
        }
    }

    private func readCapture(_ url: URL, date: Date, hasScreenshotName: Bool) -> Capture? {
        let isMarked = Self.isScreenshot(url)
        // WebP conversion may strip the macOS screenshot attribute while preserving the filename.
        let isConverted = hasScreenshotName && url.pathExtension.lowercased() == "webp"
        guard isMarked || isConverted,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              size > 0, size <= Self.maximumImageBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumImageBytes else { return nil }

        let type: String
        if url.pathExtension.lowercased() == "pdf", data.starts(with: "%PDF-".utf8) {
            type = UTType.pdf.identifier
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  let imageType = CGImageSourceGetType(source) else { return nil }
            type = imageType as String
            guard isMarked || type == UTType.webP.identifier else { return nil }
        }
        return Capture(name: url.lastPathComponent, date: date, type: type, data: data)
    }

    private static func timestampedScreenshotName(_ url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
        return name.range(of: screenshotNamePattern, options: .regularExpression) == nil ? nil : name
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return bytes.withUnsafeMutableBytes { buffer in
                getxattr(path, screenshotAttribute, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
            }
        }
        guard count > 0 else { return false }
        let value = try? PropertyListSerialization.propertyList(from: Data(bytes.prefix(count)), format: nil)
        return value as? Bool == true
    }
}
