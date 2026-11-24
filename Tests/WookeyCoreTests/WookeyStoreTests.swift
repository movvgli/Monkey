import AppKit
import Testing
@testable import WookeyCore

@MainActor
struct WookeyStoreTests {
    @Test func createsTemplateWithItsRichContentInOneSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root)
        let link = URL(string: "https://example.com")!
        let document = NSAttributedString(string: "첫 문장\n둘째 문장", attributes: [.link: link])
        let id = try #require(store.addTemplate(name: "답변", document: document))

        let reloaded = WookeyStore(rootURL: root)
        reloaded.load()
        #expect(reloaded.templates.first?.name == "답변")
        #expect(reloaded.templates.first?.plainText == document.string)
        #expect(reloaded.templateDocument(id: id).attribute(.link, at: 0, effectiveRange: nil) as? URL == link)
    }

    @Test func failedTemplateCreationLeavesNoEmptyTemplateOrDocument() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? files.removeItem(at: root) }
        try files.createDirectory(at: root.appendingPathComponent("config.json"), withIntermediateDirectories: true)

        let store = WookeyStore(rootURL: root)
        #expect(store.addTemplate(name: "답변", document: NSAttributedString(string: "본문")) == nil)
        #expect(store.templates.isEmpty)
        #expect(store.lastPersistenceError != nil)
        #expect(try files.contentsOfDirectory(atPath: root.appendingPathComponent("Templates").path).isEmpty)
    }

    @Test func templateTriggersPersistAndNewWorkflowReferencesTheTemplate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WookeyStore(rootURL: root)
        let id = try #require(store.addTemplate(name: "인사말", document: NSAttributedString(string: "안녕하세요")))
        let index = try #require(store.templates.firstIndex(where: { $0.id == id }))
        let shortcut = ShortcutGesture(steps: [.init(keyCode: 40, modifiers: [.control, .option])])
        store.templates[index].shortcut = shortcut
        store.templates[index].keywords = ["hi", "인사"]
        store.templates[index].deliveryMode = .copyAndPaste
        let workflowID = try #require(store.createWorkflow(fromTemplate: id))
        store.saveTemplateDocument(NSAttributedString(string: "수정한 인사말"), for: id)

        let reloaded = WookeyStore(rootURL: root)
        reloaded.load()
        let template = try #require(reloaded.templates.first)
        let workflow = try #require(reloaded.workflows.first(where: { $0.id == workflowID }))
        #expect(template.shortcut == shortcut)
        #expect(template.keywords == ["hi", "인사"])
        #expect(template.deliveryMode == .copyAndPaste)
        #expect(workflow.name == "인사말")
        #expect(workflow.actions == [.copyTemplate(templateID: id, mode: .copyAndPaste)])
        #expect(workflow.shortcut.steps.isEmpty && workflow.keywords.isEmpty)
        #expect(reloaded.templateDocument(id: id).string == "수정한 인사말")
    }

    @Test func legacyTemplateWithoutDirectTriggersLoadsWithCopyDefault() throws {
        let id = UUID()
        let data = Data("""
            {"id":"\(id)","name":"인사말","fileName":"greeting.rtfd","plainText":"안녕하세요"}
            """.utf8)

        let template = try JSONDecoder().decode(RichTemplate.self, from: data)

        #expect(template.shortcut == nil && template.keywords == nil)
        #expect(template.deliveryAction == .copyTemplate(templateID: id, mode: .copyOnly))
    }

    @Test func stateAndRichTemplateRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WookeyStore(rootURL: root)
        store.load()
        let workflowID = store.addWorkflow()
        let templateID = store.addTemplate()
        let appGesture = ShortcutGesture(steps: [
            KeyChord(keyCode: 0, modifiers: [.control, .option]),
        ])
        store.setApplicationShortcut(
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "텍스트 편집기",
            shortcut: appGesture
        )
        let document = NSAttributedString(
            string: "서식 템플릿",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 15), .link: URL(string: "https://example.com")!]
        )
        store.saveTemplateDocument(document, for: templateID)

        let reloaded = WookeyStore(rootURL: root)
        reloaded.load()
        #expect(reloaded.workflows.first?.id == workflowID)
        #expect(reloaded.templateDocument(id: templateID).string == "서식 템플릿")
        #expect(reloaded.applicationShortcuts.first?.bundleIdentifier == "com.apple.TextEdit")
        #expect(reloaded.applicationShortcuts.first?.shortcut == appGesture)
        #expect(reloaded.lastPersistenceError == nil)
    }

    @Test func legacyStateWithoutApplicationShortcutsStillLoads() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "workflows": [],
              "templates": [],
              "layouts": []
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(state.applicationShortcuts.isEmpty)
    }

    @Test func corruptStateStartsEmptyAndCreatesBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: root.appendingPathComponent("config.json"))

        let store = WookeyStore(rootURL: root)
        store.load()
        #expect(store.workflows.isEmpty)
        #expect(store.lastPersistenceError != nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(backups.contains(where: { $0.hasPrefix("config-corrupt-") }))
    }

    @Test func newWorkflowActionsRoundTrip() throws {
        let targetID = UUID()
        let actions: [WorkflowAction] = [
            .pressKey(.enter),
            .pressKey(.shiftEnter),
            .runWorkflow(workflowID: targetID),
            .pasteImages(filePaths: ["/tmp/sample-one.png", "/tmp/sample-two.jpg"]),
            .pasteFiles(filePaths: ["/tmp/brief.pdf", "/tmp/archive.zip"]),
        ]

        let data = try JSONEncoder().encode(actions)
        #expect(try JSONDecoder().decode([WorkflowAction].self, from: data) == actions)
    }

    @Test func deletingWorkflowRemovesReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WookeyStore(rootURL: root)
        store.load()
        let sourceID = store.addWorkflow()
        let targetID = store.addWorkflow()
        let sourceIndex = try #require(store.workflows.firstIndex(where: { $0.id == sourceID }))
        store.workflows[sourceIndex].actions = [.runWorkflow(workflowID: targetID)]
        store.save()

        store.deleteWorkflow(id: targetID)

        #expect(store.workflows.count == 1)
        #expect(store.workflows.first?.actions.isEmpty == true)
    }

    @Test func deletingTemplateRemovesWorkflowActions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WookeyStore(rootURL: root)
        store.load()
        let workflowID = store.addWorkflow()
        let templateID = store.addTemplate()
        let workflowIndex = try #require(store.workflows.firstIndex(where: { $0.id == workflowID }))
        store.workflows[workflowIndex].actions = [
            .copyTemplate(templateID: templateID, mode: .copyAndPaste),
        ]
        store.save()

        store.deleteTemplate(id: templateID)

        #expect(store.templates.isEmpty)
        #expect(store.workflows.first?.actions.isEmpty == true)
    }
}
