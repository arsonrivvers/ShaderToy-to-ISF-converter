import Foundation

public struct TextEdit: Equatable, Sendable {
    public let fromLine: Int
    public let toLine: Int
    public let replacement: String
    public let expectedContains: String?

    public init(fromLine: Int, toLine: Int, replacement: String, expectedContains: String? = nil) {
        self.fromLine = fromLine; self.toLine = toLine
        self.replacement = replacement; self.expectedContains = expectedContains
    }
}

public struct FixSuggestion: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let explanation: String
    public let edit: TextEdit?
    public let isAI: Bool

    public init(id: UUID = UUID(), title: String, explanation: String, edit: TextEdit? = nil, isAI: Bool = false) {
        self.id = id; self.title = title; self.explanation = explanation; self.edit = edit; self.isAI = isAI
    }

    public static func == (l: FixSuggestion, r: FixSuggestion) -> Bool {
        l.title == r.title && l.explanation == r.explanation && l.edit == r.edit && l.isAI == r.isAI
    }
}
