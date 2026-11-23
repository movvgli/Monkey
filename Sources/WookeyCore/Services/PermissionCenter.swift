import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
public final class PermissionCenter {
    public private(set) var accessibilityGranted = false
    public private(set) var inputMonitoringGranted = false
    public private(set) var inputMonitoringRestartRecommended = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init() {
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    public func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        if inputMonitoringGranted {
            inputMonitoringRestartRecommended = false
        }
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        scheduleRefresh()
    }

    public func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        inputMonitoringRestartRecommended = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            self.refresh()
            if !self.inputMonitoringGranted {
                self.openInputMonitoringSettings()
            }
        }
    }

    public func relaunchApplication() {
        // Start the new instance only after this one exits, so it can register the
        // exclusive global hotkeys this process still holds. Wait at most ~10s; if
        // this process is somehow still alive then, don't start a second copy.
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done; kill -0 \"$1\" 2>/dev/null && exit 0; exec /usr/bin/open \"$2\"",
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        if (try? relauncher.run()) != nil {
            NSApp.terminate(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }

    public func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    public func openInputMonitoringSettings() {
        openSettings(anchor: "Privacy_ListenEvent")
    }

    private func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
}
