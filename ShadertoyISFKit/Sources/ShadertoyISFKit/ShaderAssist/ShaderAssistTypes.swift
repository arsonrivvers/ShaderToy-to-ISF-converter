import Foundation

public enum ShaderAssistTask: Sendable, Equatable {
    case diagnoseAndFix
    case suggestionGoals
    case suggestions(goal: String)
    case applySuggestions(goal: String, selectedIdeas: [AIIdea])
    /// Research tab: mine the loaded skill knowledge for concrete upgrade ideas serving a free-text
    /// user request. Returns the same ideas schema as `.suggestions` so selection/apply are shared.
    case research(request: String)
}

public struct AIEdit: Codable, Equatable, Sendable {
    public let fromLine: Int
    public let toLine: Int
    public let replacement: String
    public let rationale: String

    public init(fromLine: Int, toLine: Int, replacement: String, rationale: String) {
        self.fromLine = fromLine
        self.toLine = toLine
        self.replacement = replacement
        self.rationale = rationale
    }
}

public struct AIFixResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let edits: [AIEdit]
}

public struct AISuggestionGoal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let whyThisShader: String

    public init(id: String, title: String, detail: String, kind: String, whyThisShader: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.whyThisShader = whyThisShader
    }
}

public struct AISuggestionGoalsResult: Codable, Equatable, Sendable {
    public let goals: [AISuggestionGoal]

    public init(goals: [AISuggestionGoal]) {
        self.goals = goals
    }
}

public struct AIIdea: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let lines: [Int]?
    public let impact: String?

    public init(id: String, title: String, detail: String, kind: String, lines: [Int]?, impact: String?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.lines = lines
        self.impact = impact
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, kind, lines, impact
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? title
        detail = try c.decode(String.self, forKey: .detail)
        kind = try c.decode(String.self, forKey: .kind)
        lines = try c.decodeIfPresent([Int].self, forKey: .lines)
        impact = try c.decodeIfPresent(String.self, forKey: .impact)
    }
}

public struct AISuggestionsResult: Codable, Equatable, Sendable {
    public let goal: String
    public let ideas: [AIIdea]

    public init(goal: String, ideas: [AIIdea]) {
        self.goal = goal
        self.ideas = ideas
    }

    private enum CodingKeys: String, CodingKey {
        case goal, ideas
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        ideas = try c.decode([AIIdea].self, forKey: .ideas)
    }
}

public struct AIApplyResult: Codable, Equatable, Sendable {
    public let explanation: String
    public let replacementSource: String
    public let changedLines: [Int]

    public init(explanation: String, replacementSource: String, changedLines: [Int]) {
        self.explanation = explanation
        self.replacementSource = replacementSource
        self.changedLines = changedLines
    }
}

public enum ShaderAssistParseError: Error, Equatable {
    /// No JSON object could be located in the output at all.
    case unparseable(raw: String)
    /// JSON was found but didn't decode — `detail` carries the field-level DecodingError reason
    /// (e.g. which key was missing) so almost-valid responses are debuggable without re-reading raw.
    case malformed(detail: String, raw: String)
    /// The CLI reported an error envelope (`is_error: true`) — `message` is its actual error text
    /// (quota, auth, timeout), previously discarded as unparseable(raw: "").
    case cliError(message: String)
}
