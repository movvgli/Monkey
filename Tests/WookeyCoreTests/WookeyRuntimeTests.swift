import Foundation
import Testing
@testable import WookeyCore

@MainActor
struct WookeyRuntimeTests {
    @Test func onlyApplicationRunsPopulateApplicationLaunchErrors() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtime = WookeyRuntime(storeRootURL: root)
        let application = ApplicationShortcut(bundleIdentifier: "test.application", displayName: "Test App")
        runtime.store.applicationShortcuts = [application]
        let failure = ActionFailure(actionTitle: "실행", message: "실패")

        runtime.runner.onSummary?(RunSummary(
            workflowID: UUID(), workflowName: "일반 워크플로",
            startedAt: .now, finishedAt: .now, failures: [failure]
        ))
        #expect(runtime.applicationLaunchErrors.isEmpty)
        #expect(runtime.lastRun?.workflowName == "일반 워크플로")

        runtime.runner.onSummary?(RunSummary(
            workflowID: application.id, workflowName: application.displayName,
            startedAt: .now, finishedAt: .now, failures: [failure]
        ))
        #expect(runtime.applicationLaunchError(bundleIdentifier: application.bundleIdentifier) == "실패")
        #expect(runtime.applicationName(runID: application.id) == application.displayName)

        runtime.runner.onSummary?(RunSummary(
            workflowID: application.id, workflowName: application.displayName,
            startedAt: .now, finishedAt: .now, failures: []
        ))
        #expect(runtime.applicationLaunchErrors.isEmpty)
    }
}

@MainActor
struct ApplicationControllerOpenFileTests {
    @Test func scriptsAndExecutablesAreNotOpened() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["run.command", "run.tool", "run.terminal"] {
            let url = directory.appendingPathComponent(name)
            try Data("echo hi\n".utf8).write(to: url)
            #expect(ApplicationController.isExecutableDocument(url), "\(name)")
        }
        // An extensionless file with the execute bit opens (and runs) in Terminal.
        let binary = directory.appendingPathComponent("run")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        #expect(ApplicationController.isExecutableDocument(binary))

        // Plain scripts and documents open in their editor, so they stay allowed.
        for name in ["note.txt", "script.sh", "script.py"] {
            let url = directory.appendingPathComponent(name)
            try Data("hi".utf8).write(to: url)
            #expect(!ApplicationController.isExecutableDocument(url), "\(name)")
        }
    }

    @Test func openFileRejectsExecutableDocument() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).command")
        try Data("echo hi\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: AutomationError.self) {
            try await ApplicationController().openFile(at: url.path)
        }
    }
}
