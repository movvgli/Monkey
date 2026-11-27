import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class ApplicationController {
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    public init() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.rememberExternalApplication(application) }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    private func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Clicking Run inside Wookey should still type into the last external app.
    public func inputTargetApplication() -> NSRunningApplication? {
        rememberExternalApplication(frontmostApplication())
        guard let application = lastExternalApplication, !application.isTerminated else { return nil }
        return application
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              !application.isTerminated else { return }
        lastExternalApplication = application
    }

    @discardableResult
    public func launch(bundleIdentifier: String, activates: Bool = true) async throws -> NSRunningApplication {
        try Task.checkCancellation()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw AutomationError.applicationNotFound(bundleIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        configuration.addsToRecentItems = false
        // Reopen through Launch Services even when already running. Merely activating
        // an app with its last window closed does not ask it to show a window again.
        let application: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: error ?? AutomationError.applicationDidNotLaunch(bundleIdentifier))
                }
            }
        }
        try Task.checkCancellation()
        if activates { try await Self.activateAndWait(application) }
        return application
    }

    @discardableResult
    public func openURL(_ value: String) async throws -> NSRunningApplication {
        try Task.checkCancellation()
        guard let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            throw AutomationError.invalidURL(value)
        }
        return try await open(url, fallbackName: L10n.text("웹 브라우저"))
    }

    @discardableResult
    public func openFile(at path: String) async throws -> NSRunningApplication {
        try Task.checkCancellation()
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw AutomationError.fileNotFound(URL(fileURLWithPath: path).lastPathComponent)
        }
        let url = URL(fileURLWithPath: path)
        // Opening a script or executable through Launch Services runs it (often in
        // Terminal); a workflow step that "opens a file" must never execute code.
        guard !Self.isExecutableDocument(url) else {
            throw AutomationError.executableFileNotAllowed(url.lastPathComponent)
        }
        return try await open(url, fallbackName: url.lastPathComponent)
    }

    // Types Launch Services *runs* when opened, plus pointer documents that make it
    // open another file or an arbitrary URL (which would bypass openURL's http/https
    // allowlist). Plain scripts such as .sh or .py open in their default editor, so
    // they stay allowed.
    private static let executableExtensions: Set<String> = [
        "command", "tool", "terminal", "jar", "inetloc", "fileloc", "webloc", "afploc", "ftploc",
    ]
    private static let executableTypes: [UTType] = [
        .unixExecutable, UTType("com.apple.terminal.shell-script"), UTType("com.sun.java-archive"),
        UTType("com.apple.web-internet-location"), UTType("com.apple.internet-location"),
        UTType("com.apple.file-location"),
    ].compactMap { $0 }

    static func isExecutableDocument(_ url: URL) -> Bool {
        // Judge what will actually be opened: a symlink's own content type is
        // public.symlink, which would hide the target's executable type.
        let candidates = [url, url.resolvingSymlinksInPath()]
        return candidates.contains { candidate in
            if executableExtensions.contains(candidate.pathExtension.lowercased()) { return true }
            let contentType = (try? candidate.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                ?? UTType(filenameExtension: candidate.pathExtension)
            guard let contentType else { return false }
            return executableTypes.contains { contentType.conforms(to: $0) }
        }
    }

    private func open(_ url: URL, fallbackName: String) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: configuration) { app, error in
                if let error { continuation.resume(throwing: error) }
                else if let app { continuation.resume(returning: app) }
                else { continuation.resume(throwing: AutomationError.applicationDidNotLaunch(fallbackName)) }
            }
        }
        try Task.checkCancellation()
        try await Self.activateAndWait(application)
        return application
    }

    static func activateAndWait(_ application: NSRunningApplication) async throws {
        try Task.checkCancellation()
        let name = application.localizedName ?? application.bundleIdentifier ?? L10n.text("앱")
        guard !application.isTerminated else {
            throw AutomationError.applicationDidNotLaunch(name)
        }
        if !application.isActive { application.activate() }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            try Task.checkCancellation()
            guard !application.isTerminated else {
                throw AutomationError.applicationDidNotLaunch(name)
            }
            if application.isFinishedLaunching,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                // Activation notifications precede a newly visible window receiving focus.
                try await Task.sleep(for: .milliseconds(150))
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AutomationError.applicationDidNotActivate(name)
    }
}

public enum AutomationError: LocalizedError {
    case applicationNotFound(String)
    case applicationDidNotLaunch(String)
    case applicationDidNotActivate(String)
    case inputTargetNotFound
    case shortcutKeysStillPressed
    case invalidURL(String)
    case templateNotFound
    case layoutNotFound
    case permissionRequired(String)
    case clipboardWriteFailed
    case imageNotFound(String)
    case fileNotFound(String)
    case executableFileNotAllowed(String)
    case keyboardEventCreationFailed
    case workflowNotFound
    case workflowAlreadyRunning
    case workflowIsEmpty
    case invalidWaitDuration
    case workflowCycleDetected
    case displayNotFound(String)
    case windowNotFound(String)
    case windowIsFullScreen(String)
    case windowMoveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .applicationNotFound(let id): L10n.text("설치된 앱을 찾을 수 없습니다: \(id)")
        case .applicationDidNotLaunch(let id): L10n.text("앱을 실행하지 못했습니다: \(id)")
        case .applicationDidNotActivate(let name): L10n.text("‘\(name)’ 앱으로 전환하지 못했습니다. 앱을 연 뒤 다시 실행해 주세요.")
        case .inputTargetNotFound: L10n.text("입력할 앱을 찾지 못했습니다. 대상 앱을 열거나 워크플로 첫 단계에 앱 실행을 추가해 주세요.")
        case .shortcutKeysStillPressed: L10n.text("단축키에서 손을 뗀 뒤 다시 실행해 주세요.")
        case .invalidURL(let url): L10n.text("유효한 HTTP/HTTPS 주소가 아닙니다: \(url)")
        case .templateNotFound: L10n.text("템플릿을 찾을 수 없습니다.")
        case .layoutNotFound: L10n.text("레이아웃을 찾을 수 없습니다.")
        case .permissionRequired(let name): L10n.text("\(name) 권한이 필요합니다.")
        case .clipboardWriteFailed: L10n.text("클립보드에 내용을 기록하지 못했습니다.")
        case .imageNotFound(let name): L10n.text("이미지를 찾거나 열 수 없습니다: \(name)")
        case .fileNotFound(let name): L10n.text("파일을 찾을 수 없습니다: \(name)")
        case .executableFileNotAllowed(let name): L10n.text("실행 파일이나 스크립트는 열 수 없습니다: \(name)")
        case .keyboardEventCreationFailed: L10n.text("키 입력을 만들지 못했습니다.")
        case .workflowNotFound: L10n.text("연결된 워크플로를 찾을 수 없습니다.")
        case .workflowAlreadyRunning: L10n.text("이 워크플로가 이미 실행 또는 대기 중입니다.")
        case .workflowIsEmpty: L10n.text("워크플로에 실행할 동작을 먼저 추가해 주세요.")
        case .invalidWaitDuration: L10n.text("대기 시간은 0초보다 길고 30초 이하여야 합니다.")
        case .workflowCycleDetected: L10n.text("워크플로가 서로 반복 실행되도록 연결되어 중단했습니다.")
        case .displayNotFound(let name): L10n.text("연결된 모니터를 찾을 수 없습니다: \(name)")
        case .windowNotFound(let app): L10n.text("10초 안에 ‘\(app)’ 창을 찾지 못했습니다.")
        case .windowIsFullScreen(let app): L10n.text("‘\(app)’의 전체 화면 창은 이동하지 않았습니다.")
        case .windowMoveFailed(let app): L10n.text("‘\(app)’ 창의 크기나 위치를 변경할 수 없습니다.")
        }
    }
}
