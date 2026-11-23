import Foundation
import Testing
@testable import MonkeyCore

struct WorkflowKeywordTests {
    @Test func exactKeywordRanksBeforePrefixIgnoringCase() {
        let prefix = Workflow(actions: [.wait(seconds: 0)], keyword: "gcalendar")
        let exact = Workflow(actions: [.openURL("https://calendar.google.com/")], keyword: "gcal")
        #expect(WorkflowKeyword.matches("  GCAL ", in: [prefix, exact]).map { $0.workflow.id } == [exact.id, prefix.id])
        #expect(WorkflowKeyword.matches("gcal extra", in: [prefix, exact]).isEmpty)
    }

    @Test func duplicateAndEmptyWorkflowsCannotRunFromKeywords() {
        let first = Workflow(name: "캘린더", actions: [.wait(seconds: 0)], keyword: "gcal")
        let duplicate = Workflow(actions: [.wait(seconds: 0)], keyword: "GCAL")
        let empty = Workflow(keyword: "gcalc")
        #expect(WorkflowKeyword.matches("gcal", in: [first, duplicate, empty]).isEmpty)
        #expect(WorkflowKeyword.validationMessage(for: "GCAL", excluding: first.id, in: [first]) == nil)
        #expect(WorkflowKeyword.validationMessage(for: "GCAL", in: [first]) != nil)
        #expect(WorkflowKeyword.validationMessage(for: "g cal", in: []) != nil)
    }

    @Test func aliasesFindLinksAndAppsOnceAndPreferTheExactMatch() throws {
        let aliases = try #require(WorkflowKeyword.parseList(" gcalendar, GCAL, 구글캘, ㅎㅊ미, gcal "))
        #expect(aliases == ["gcalendar", "gcal", "구글캘", "ㅎㅊ미"])
        #expect(WorkflowKeyword.parseList("gcal, ") == ["gcal"])
        #expect(WorkflowKeyword.parseList("gcal, 구글 캘") == nil)

        let prefix = Workflow(actions: [.wait(seconds: 0)], keyword: "gcal2")
        var link = Workflow(actions: [.openURL("https://calendar.google.com/")])
        link.keywords = aliases
        var app = Workflow(actions: [.launchApplication(bundleIdentifier: "com.apple.iCal", displayName: "캘린더")])
        app.keywords = ["calendar", "캘린더"]
        let workflows = [prefix, link, app]

        let ranked = WorkflowKeyword.matches("gcal", in: workflows)
        #expect(ranked.map { $0.workflow.id } == [link.id, prefix.id])
        #expect(ranked.first?.keyword == "gcal")
        #expect(WorkflowKeyword.matches("구글캘", in: workflows).first?.workflow.id == link.id)
        #expect(WorkflowKeyword.matches("ㅎㅊ미", in: workflows).first?.workflow.id == link.id)
        #expect(WorkflowKeyword.matches("캘린더", in: workflows).first?.workflow.id == app.id)
    }

    @Test func sharedAliasesAreRejectedWithoutHidingOtherAliases() {
        var first = Workflow(name: "캘린더", actions: [.wait(seconds: 0)])
        first.keywords = ["gcal", "calendar"]
        var second = Workflow(actions: [.wait(seconds: 0)])
        second.keywords = ["dates", "CALENDAR"]
        let workflows = [first, second]

        #expect(WorkflowKeyword.validationMessage(for: "other, CALENDAR", in: [first]) != nil)
        #expect(WorkflowKeyword.validationMessage(for: "gcal, CALENDAR", excluding: first.id, in: [first]) == nil)
        #expect(WorkflowKeyword.matches("calendar", in: workflows).isEmpty)
        #expect(WorkflowKeyword.matches("gcal", in: workflows).first?.workflow.id == first.id)
        #expect(WorkflowKeyword.matches("dates", in: workflows).first?.workflow.id == second.id)
    }

    @Test func oldConfigurationsDecodeAndNewSearchSettingsRoundTrip() throws {
        let json = """
            {"schemaVersion":1,"workflows":[{"id":"12E0A0CF-4417-4901-A6EE-F5B1AB8FD0D6","name":"기존",
            "isEnabled":true,"shortcut":{"steps":[]},"actions":[]}],"templates":[],"layouts":[]}
            """
        let decoder = JSONDecoder()
        var state = try decoder.decode(PersistedState.self, from: Data(json.utf8))
        #expect(state.workflows.first?.keywords.isEmpty == true)
        #expect(state.searchShortcut == nil)
        state.workflows[0].keyword = "gcal"
        let legacy = try decoder.decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(legacy.workflows.first?.keywords == ["gcal"])

        state.workflows[0].keywords = ["gcal", "구글캘", "ㅎㅊ미"]
        state.searchShortcut = .init()
        let reloaded = try decoder.decode(PersistedState.self, from: JSONEncoder().encode(state))
        #expect(reloaded.workflows.first?.keyword == "gcal")
        #expect(reloaded.workflows.first?.keywords == ["gcal", "구글캘", "ㅎㅊ미"])
        #expect(reloaded.searchShortcut?.steps == [])
    }
}

struct WorkflowDependencyGraphTests {
    @Test func rejectsSelfReference() {
        let workflow = Workflow()

        #expect(
            WorkflowDependencyGraph.wouldCreateCycle(
                from: workflow.id,
                to: workflow.id,
                in: [workflow]
            )
        )
    }

    @Test func rejectsIndirectCycle() {
        var first = Workflow(name: "첫 번째")
        var second = Workflow(name: "두 번째")
        let third = Workflow(name: "세 번째")
        first.actions = [.runWorkflow(workflowID: second.id)]
        second.actions = [.runWorkflow(workflowID: third.id)]

        #expect(
            WorkflowDependencyGraph.wouldCreateCycle(
                from: third.id,
                to: first.id,
                in: [first, second, third]
            )
        )
        #expect(
            !WorkflowDependencyGraph.wouldCreateCycle(
                from: first.id,
                to: third.id,
                in: [first, second, third]
            )
        )
    }
}
