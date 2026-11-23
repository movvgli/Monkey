import AppIntents
import Foundation
import WookeyCore

struct WikeyWorkflowEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wookey 워크플로"
    static let defaultQuery = WikeyWorkflowQuery()

    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WikeyWorkflowQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [WikeyWorkflowEntity] {
        let byID = Dictionary(uniqueKeysWithValues: workflows().map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    @MainActor
    func suggestedEntities() async throws -> [WikeyWorkflowEntity] { workflows() }

    @MainActor
    func entities(matching string: String) async throws -> [WikeyWorkflowEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return workflows().filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    @MainActor
    private func workflows() -> [WikeyWorkflowEntity] {
        WookeyAppRuntime.start().store.workflows.compactMap { workflow in
            guard !workflow.actions.isEmpty else { return nil }
            return WikeyWorkflowEntity(id: workflow.id, name: workflow.name)
        }
    }
}

struct RunWikeyWorkflowIntent: AppIntent {
    static let title: LocalizedStringResource = "Wookey 워크플로 실행"
    static let description = IntentDescription("Wookey에서 저장한 자동화를 실행합니다.")

    @Parameter(title: "워크플로")
    var workflow: WikeyWorkflowEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$workflow) 실행")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let summary = try await WookeyAppRuntime.start().runner.runAndWait(workflowID: workflow.id)
        if let failure = summary.failures.first {
            throw WookeyIntentExecutionError(message: failure.message)
        }
        return .result()
    }
}

private struct WookeyIntentExecutionError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
