import Foundation

public struct Workflow: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var shortcut: ShortcutGesture
    public var actions: [WorkflowAction]
    public var keyword: String?
    private var additionalKeywords: [String]?

    // Keep the first keyword readable by versions that only support one.
    public var keywords: [String] {
        get { [keyword].compactMap { $0 } + (additionalKeywords ?? []) }
        set {
            keyword = newValue.first
            additionalKeywords = newValue.count > 1 ? Array(newValue.dropFirst()) : nil
        }
    }

    public init(
        id: UUID = UUID(),
        name: String = L10n.text("새 워크플로"),
        isEnabled: Bool = true,
        shortcut: ShortcutGesture = .init(),
        actions: [WorkflowAction] = [],
        keyword: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.shortcut = shortcut
        self.actions = actions
        self.keyword = keyword
    }
}

public enum WorkflowKeyword {
    public struct Match {
        public let workflow: Workflow
        public let keyword: String
    }

    public static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard (1...32).contains(token.count),
              token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return token.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public static func parseList(_ text: String) -> [String]? {
        var tokens: [String] = []
        var seen = Set<String>()
        for part in text.split(separator: ",") {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            guard let token = normalized(value) else { return nil }
            if seen.insert(token).inserted { tokens.append(token) }
        }
        return tokens
    }

    public static func validationMessage(
        for text: String, excluding id: UUID? = nil, in workflows: [Workflow],
        templates: [RichTemplate] = [], excludingTemplate templateID: UUID? = nil
    ) -> String? {
        guard let tokens = parseList(text) else { return L10n.text("키워드마다 공백 없이 문자·숫자·하이픈·밑줄을 32자까지 입력하세요.") }
        let requested = Set(tokens)
        for workflow in workflows where workflow.id != id {
            if let conflict = workflow.keywords.compactMap(normalized).first(where: requested.contains) {
                return L10n.text("‘\(conflict)’ 키워드는 ‘\(workflow.name)’에서 이미 사용 중입니다.")
            }
        }
        for template in templates where template.id != templateID {
            if let conflict = (template.keywords ?? []).compactMap(normalized).first(where: requested.contains) {
                return L10n.text("‘\(conflict)’ 키워드는 ‘\(template.name)’에서 이미 사용 중입니다.")
            }
        }
        return nil
    }

    public static func matches(_ query: String, in workflows: [Workflow]) -> [Match] {
        matches(query, in: workflows, templates: []).compactMap { match in
            if case .workflow(let workflow) = match.target { return Match(workflow: workflow, keyword: match.keyword) }
            return nil
        }
    }

    public enum Target {
        case workflow(Workflow)
        case template(RichTemplate)

        fileprivate enum ID: Hashable { case workflow(UUID), template(UUID) }
        fileprivate var id: ID {
            switch self {
            case .workflow(let workflow): .workflow(workflow.id)
            case .template(let template): .template(template.id)
            }
        }
        fileprivate var keywords: [String] {
            switch self {
            case .workflow(let workflow): workflow.keywords
            case .template(let template): template.keywords ?? []
            }
        }
        fileprivate var canRun: Bool {
            if case .workflow(let workflow) = self { return !workflow.actions.isEmpty }
            return true
        }
    }

    public struct TargetMatch {
        public let target: Target
        public let keyword: String
    }

    public static func matches(_ query: String, in workflows: [Workflow], templates: [RichTemplate]) -> [TargetMatch] {
        guard let token = normalized(query) else { return [] }
        let targets = workflows.map(Target.workflow) + templates.map(Target.template)
        let candidates = targets.flatMap { target in
            var seen = Set<String>()
            return target.keywords.compactMap(normalized).compactMap { keyword -> TargetMatch? in
                guard keyword.hasPrefix(token), seen.insert(keyword).inserted else { return nil }
                return TargetMatch(target: target, keyword: keyword)
            }
        }
        let grouped = Dictionary(grouping: candidates, by: \.keyword)
        // Imports and sync can produce ambiguous aliases across workflows and templates.
        let unique = candidates.filter { grouped[$0.keyword]?.count == 1 && $0.target.canRun }
        let ranked = unique.filter { $0.keyword == token } + unique.filter { $0.keyword != token }
        var matchedTargets = Set<Target.ID>()
        return ranked.filter { matchedTargets.insert($0.target.id).inserted }
    }
}

public struct ApplicationShortcut: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var displayName: String
    public var shortcut: ShortcutGesture

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        shortcut: ShortcutGesture = .init()
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.shortcut = shortcut
    }
}

public enum TemplateDeliveryMode: String, Codable, CaseIterable, Sendable {
    case copyOnly
    case copyAndPaste

    public var title: String {
        switch self {
        case .copyOnly: L10n.text("클립보드에 복사")
        case .copyAndPaste: L10n.text("복사 후 자동 붙여넣기")
        }
    }
}

public enum WorkflowKeyPress: String, Codable, CaseIterable, Sendable {
    case enter
    case shiftEnter

    public var title: String {
        switch self {
        case .enter: "Enter"
        case .shiftEnter: "Shift + Enter"
        }
    }
}

public enum WorkflowAction: Identifiable, Codable, Hashable, Sendable {
    case launchApplication(bundleIdentifier: String, displayName: String)
    case copyTemplate(templateID: UUID, mode: TemplateDeliveryMode)
    case openURL(String)
    case openFile(path: String)
    case applyLayout(layoutID: UUID)
    case pressKey(WorkflowKeyPress)
    case runWorkflow(workflowID: UUID)
    case pasteImages(filePaths: [String])
    case pasteFiles(filePaths: [String])
    case wait(seconds: Double)

    public var id: String {
        switch self {
        case .launchApplication(let bundleID, _): "app:\(bundleID)"
        case .copyTemplate(let id, _): "template:\(id)"
        case .openFile(let path): "open-file:\(path)"
        case .openURL(let url): "url:\(url)"
        case .applyLayout(let id): "layout:\(id)"
        case .pressKey(let key): "key:\(key.rawValue)"
        case .runWorkflow(let id): "workflow:\(id)"
        case .pasteImages(let paths): "images:\(paths.joined(separator: "|"))"
        case .pasteFiles(let paths): "files:\(paths.joined(separator: "|"))"
        case .wait(let seconds): "wait:\(seconds)"
        }
    }

    public var title: String {
        switch self {
        case .launchApplication(_, let name): L10n.text("앱 실행 · \(name)")
        case .copyTemplate: L10n.text("템플릿 붙여넣기")
        case .openURL: L10n.text("링크 열기")
        case .openFile: L10n.text("파일 열기")
        case .applyLayout: L10n.text("창 레이아웃 적용")
        case .pressKey(let key): L10n.text("\(key.title) 입력")
        case .runWorkflow: L10n.text("다른 워크플로 실행")
        case .pasteImages: L10n.text("이미지 붙여넣기")
        case .pasteFiles: L10n.text("파일 붙여넣기")
        case .wait: L10n.text("잠시 기다리기")
        }
    }
}

public enum WorkflowDependencyGraph {
    public static func wouldCreateCycle(
        from sourceID: UUID,
        to targetID: UUID,
        in workflows: [Workflow]
    ) -> Bool {
        if sourceID == targetID { return true }

        let workflowsByID = Dictionary(workflows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pending = [targetID]
        var visited = Set<UUID>()

        while let currentID = pending.popLast() {
            if currentID == sourceID { return true }
            guard visited.insert(currentID).inserted,
                  let current = workflowsByID[currentID] else { continue }

            pending.append(contentsOf: current.actions.compactMap { action in
                guard case .runWorkflow(let workflowID) = action else { return nil }
                return workflowID
            })
        }

        return false
    }
}

public struct RichTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var fileName: String
    public var plainText: String
    public var shortcut: ShortcutGesture?
    public var keywords: [String]?
    public var deliveryMode: TemplateDeliveryMode?

    public var deliveryAction: WorkflowAction {
        .copyTemplate(templateID: id, mode: deliveryMode ?? .copyOnly)
    }

    public init(id: UUID = UUID(), name: String = L10n.text("새 템플릿"), plainText: String = "") {
        self.id = id
        self.name = name
        self.fileName = "\(id.uuidString).rtfd"
        self.plainText = plainText
    }
}

public enum LayoutZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case leftHalf, rightHalf
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case leftOneThird, rightOneThird
    case topLeft, topRight, bottomLeft, bottomRight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: L10n.text("전체")
        case .leftHalf: L10n.text("왼쪽 1/2")
        case .rightHalf: L10n.text("오른쪽 1/2")
        case .leftThird: L10n.text("왼쪽 1/3")
        case .centerThird: L10n.text("가운데 1/3")
        case .rightThird: L10n.text("오른쪽 1/3")
        case .leftTwoThirds: L10n.text("왼쪽 2/3")
        case .rightTwoThirds: L10n.text("오른쪽 2/3")
        case .leftOneThird: L10n.text("왼쪽 1/3")
        case .rightOneThird: L10n.text("오른쪽 1/3")
        case .topLeft: L10n.text("왼쪽 위 1/4")
        case .topRight: L10n.text("오른쪽 위 1/4")
        case .bottomLeft: L10n.text("왼쪽 아래 1/4")
        case .bottomRight: L10n.text("오른쪽 아래 1/4")
        }
    }

    public var normalizedRect: CGRect {
        switch self {
        case .full: CGRect(x: 0, y: 0, width: 1, height: 1)
        case .leftHalf: CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .leftThird, .leftOneThird: CGRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        case .centerThird: CGRect(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        case .rightThird, .rightOneThird: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        case .leftTwoThirds: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1)
        case .rightTwoThirds: CGRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
        case .topLeft: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .topRight: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .bottomLeft: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .bottomRight: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        }
    }

    public func frame(in visibleFrame: CGRect) -> CGRect {
        let rect = normalizedRect
        return CGRect(
            x: visibleFrame.minX + visibleFrame.width * rect.minX,
            y: visibleFrame.minY + visibleFrame.height * rect.minY,
            width: visibleFrame.width * rect.width,
            height: visibleFrame.height * rect.height
        ).integral
    }
}

public struct DisplayTarget: Codable, Hashable, Sendable {
    public var uuid: String
    public var name: String

    public init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }
}

public struct AppWindowPlacement: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var appName: String
    public var display: DisplayTarget
    public var zone: LayoutZone

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        appName: String,
        display: DisplayTarget,
        zone: LayoutZone = .full
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.display = display
        self.zone = zone
    }
}

public struct WindowLayout: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var placements: [AppWindowPlacement]
    public var shortcut: ShortcutGesture

    public init(id: UUID = UUID(), name: String = L10n.text("새 레이아웃"), placements: [AppWindowPlacement] = [], shortcut: ShortcutGesture = .init()) {
        self.id = id
        self.name = name
        self.placements = placements
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, placements, shortcut
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        placements = try values.decode([AppWindowPlacement].self, forKey: .placements)
        shortcut = try values.decodeIfPresent(ShortcutGesture.self, forKey: .shortcut) ?? .init()
    }
}

public struct PersistedState: Codable, Sendable {
    public var schemaVersion: Int
    public var workflows: [Workflow]
    public var templates: [RichTemplate]
    public var layouts: [WindowLayout]
    public var applicationShortcuts: [ApplicationShortcut]
    public var searchShortcut: ShortcutGesture?

    public init(
        schemaVersion: Int = 1,
        workflows: [Workflow] = [],
        templates: [RichTemplate] = [],
        layouts: [WindowLayout] = [],
        applicationShortcuts: [ApplicationShortcut] = [],
        searchShortcut: ShortcutGesture? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workflows = workflows
        self.templates = templates
        self.layouts = layouts
        self.applicationShortcuts = applicationShortcuts
        self.searchShortcut = searchShortcut
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workflows
        case templates
        case layouts
        case applicationShortcuts
        case searchShortcut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        workflows = try container.decode([Workflow].self, forKey: .workflows)
        templates = try container.decode([RichTemplate].self, forKey: .templates)
        layouts = try container.decode([WindowLayout].self, forKey: .layouts)
        applicationShortcuts = try container.decodeIfPresent(
            [ApplicationShortcut].self,
            forKey: .applicationShortcuts
        ) ?? []
        searchShortcut = try container.decodeIfPresent(ShortcutGesture.self, forKey: .searchShortcut)
    }
}

public struct ActionFailure: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var actionTitle: String
    public var message: String
}

public struct RunSummary: Hashable, Sendable {
    public var workflowID: UUID? = nil
    public var workflowName: String
    public var startedAt: Date
    public var finishedAt: Date
    public var failures: [ActionFailure]

    public var menuTitle: String {
        failures.isEmpty ? L10n.text("최근 실행 성공 · \(workflowName)") : L10n.text("최근 실행 실패 \(failures.count)건 · \(workflowName)")
    }
}
